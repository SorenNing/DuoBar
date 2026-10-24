#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "DuoGlyphView.h"

// The real UIKit hierarchy is the only source of truth. The ring shows a live
// snapshot of the native Wi-Fi and cellular glyphs; the stock views are then
// folded away, and every layout pass while folded re-suppresses them, so a
// glyph the system re-shows or rebuilds can never flash back on screen.

static NSString *const kEngine = @"iya.banana.duoicon";
static NSString *const kRingKey = @"NativeDuo.Ring";
static NSString *const kRestoreKey = @"NativeDuo.Restore";
static NSString *const kActiveKey = @"NativeDuo.Active";

static CFPropertyListRef NativeCopy(NSString *key, NSString *domain) {
    return CFPreferencesCopyValue((__bridge CFStringRef)key,
        (__bridge CFStringRef)domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

static double NativeNumber(NSString *key, NSString *domain, double fallback) {
    CFPropertyListRef value = NativeCopy(key, domain);
    if (!value) return fallback;
    double result = fallback;
    if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        result = [(__bridge NSNumber *)value doubleValue];
    } else if (CFGetTypeID(value) == CFBooleanGetTypeID()) {
        result = CFBooleanGetValue((CFBooleanRef)value) ? 1 : 0;
    }
    CFRelease(value);
    return result;
}

static BOOL NativeEngineEnabled(void) {
    return NativeNumber(@"Enabled", kEngine, 1) != 0;
}

static BOOL NativeControlCenterVisible(void) {
    Class cls = NSClassFromString(@"SBControlCenterController");
    SEL shared = NSSelectorFromString(@"sharedInstance");
    if (!cls || ![cls respondsToSelector:shared]) return NO;
    id controller = ((id (*)(id, SEL))objc_msgSend)(cls, shared);
    for (NSString *name in @[@"isVisible", @"isPresented"]) {
        SEL selector = NSSelectorFromString(name);
        if ([controller respondsToSelector:selector] &&
            ((BOOL (*)(id, SEL))objc_msgSend)(controller, selector)) return YES;
    }
    return NO;
}

static BOOL NativeLocked(void) {
    Class cls = NSClassFromString(@"SBLockScreenManager");
    SEL shared = NSSelectorFromString(@"sharedInstance");
    if (!cls || ![cls respondsToSelector:shared]) return NO;
    id manager = ((id (*)(id, SEL))objc_msgSend)(cls, shared);
    for (NSString *name in @[@"isUILocked", @"isLockScreenVisible"]) {
        SEL selector = NSSelectorFromString(name);
        if ([manager respondsToSelector:selector] &&
            ((BOOL (*)(id, SEL))objc_msgSend)(manager, selector)) return YES;
    }
    return NO;
}

typedef NS_ENUM(NSInteger, DuoGlyphKind) {
    DuoGlyphKindNone = 0,
    DuoGlyphKindBattery,
    DuoGlyphKindWifi,
    DuoGlyphKindCellular,
    DuoGlyphKindOther,
};

// Render the live native glyph into a template image: the ring then draws the
// system artwork itself, tinted with the bar's own foreground colour.
static UIImage *DuoGlyphImage(UIView *view) {
    if (!view) return nil;
    CGSize size = view.bounds.size;
    if (size.width < 1.0 || size.height < 1.0) return nil;
    UIImage *image = nil;
    @try {
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
        image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            (void)context;
            [view drawViewHierarchyInRect:CGRectMake(0, 0, size.width, size.height)
                       afterScreenUpdates:NO];
        }];
    } @catch (__unused NSException *e) {
        image = nil;
    }
    return image ? [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] : nil;
}

static DuoGlyphKind DuoGlyphKindOf(UIView *view) {
    if (!view) return DuoGlyphKindNone;
    NSString *name = NSStringFromClass(view.class);
    if (name.length == 0) return DuoGlyphKindNone;
    if ([name containsString:@"BatteryView"]) return DuoGlyphKindBattery;
    if ([name containsString:@"Wifi"]) return DuoGlyphKindWifi;
    if ([name containsString:@"Cellular"]) return DuoGlyphKindCellular;
    if ([name containsString:@"SignalView"] ||
        [name isEqualToString:@"STUIStatusBarImageView"]) return DuoGlyphKindOther;
    return DuoGlyphKindNone;
}

@interface NativeController : NSObject
@property(nonatomic) BOOL transitioning;
@end

@implementation NativeController
+ (instancetype)shared {
    static NativeController *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [self new]; });
    return shared;
}

#pragma mark - Glyph discovery

// Collect the stock glyphs that live in the trailing (right) half of the bar.
// The left half carries indicators like the alarm or Do-Not-Disturb icon and
// must never be folded into the ring.
- (void)collectIn:(UIView *)parent host:(UIView *)host rightEdge:(CGFloat)rightEdge
             into:(NSMutableArray<UIView *> *)icons {
    for (UIView *sub in parent.subviews) {
        DuoGlyphKind kind = DuoGlyphKindOf(sub);
        if (kind != DuoGlyphKindNone && !sub.hidden && sub.alpha > 0.01) {
            CGRect frame = [sub convertRect:sub.bounds toView:host];
            if (CGRectGetMidX(frame) > rightEdge) {
                BOOL covered = NO;
                for (UIView *known in icons) {
                    if ([sub isDescendantOfView:known]) { covered = YES; break; }
                }
                if (!covered) [icons addObject:sub];
            }
        }
        [self collectIn:sub host:host rightEdge:rightEdge into:icons];
    }
}

- (NSMutableArray<UIView *> *)iconsIn:(UIView *)bar {
    NSMutableArray<UIView *> *icons = [NSMutableArray array];
    [self collectIn:bar host:bar rightEdge:bar.bounds.size.width * 0.5 into:icons];
    return icons;
}

#pragma mark - Native values (KVC: never assume a C return type)

- (double)doubleOf:(UIView *)view key:(NSString *)key fallback:(double)fallback {
    @try {
        id value = [view valueForKey:key];
        if ([value respondsToSelector:@selector(doubleValue)]) return [value doubleValue];
    } @catch (__unused NSException *e) {}
    return fallback;
}

- (NSInteger)integerOf:(UIView *)view key:(NSString *)key fallback:(NSInteger)fallback {
    @try {
        id value = [view valueForKey:key];
        if ([value respondsToSelector:@selector(integerValue)]) return [value integerValue];
    } @catch (__unused NSException *e) {}
    return fallback;
}

- (UIColor *)foregroundOf:(UIView *)bar {
    @try {
        id attrs = [bar valueForKey:@"styleAttributes"];
        if ([attrs respondsToSelector:@selector(objectForKey:)]) {
            UIColor *color = attrs[@"textColor"];
            if ([color isKindOfClass:UIColor.class]) return color;
        }
        UIColor *color = [bar valueForKey:@"foregroundColor"];
        if ([color isKindOfClass:UIColor.class]) return color;
    } @catch (__unused NSException *e) {}
    return UIColor.labelColor;
}

#pragma mark - Fold state

- (BOOL)isFolded:(UIView *)bar {
    return [objc_getAssociatedObject(bar, &kActiveKey) boolValue];
}

- (void)unfold:(UIView *)bar {
    NSDictionary<NSString *, NSDictionary *> *saved = objc_getAssociatedObject(bar, &kRestoreKey);
    for (NSString *key in saved) {
        NSDictionary *info = saved[key];
        UIView *view = info[@"view"];
        if (!view) continue;
        view.hidden = [info[@"hidden"] boolValue];
        view.alpha = [info[@"alpha"] doubleValue];
        view.center = [info[@"center"] CGPointValue];
        view.transform = [info[@"transform"] CGAffineTransformValue];
    }
    UIView *ring = objc_getAssociatedObject(bar, &kRingKey);
    [ring removeFromSuperview];
    objc_setAssociatedObject(bar, &kRingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(bar, &kRestoreKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(bar, &kActiveKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    self.transitioning = NO;
}

// While folded, re-suppress every stock glyph the system brings back (a
// relayout resetting `hidden`, a rebuilt icon view, a late `addSubview`).
// Each pass records the original state once, so the unfold can restore it.
- (void)maintain:(UIView *)bar {
    if (self.transitioning || ![self isFolded:bar]) return;
    NSMutableDictionary *saved = objc_getAssociatedObject(bar, &kRestoreKey);
    if (!saved) return;
    for (UIView *view in [self iconsIn:bar]) {
        NSString *key = [NSString stringWithFormat:@"%p", view];
        if (!saved[key]) {
            saved[key] = @{ @"view":view, @"hidden":@(view.hidden),
                @"alpha":@(view.alpha), @"center":[NSValue valueWithCGPoint:view.center],
                @"transform":[NSValue valueWithCGAffineTransform:view.transform] };
        }
        view.hidden = YES;
    }
}

#pragma mark - Fold

- (void)fold:(UIView *)bar {
    if (!bar || self.transitioning || [self isFolded:bar]) return;
    self.transitioning = YES;

    NSMutableArray<UIView *> *icons = [self iconsIn:bar];
    if (icons.count == 0) { self.transitioning = NO; return; }

    UIView *battery = nil, *wifi = nil, *cell = nil;
    for (UIView *view in icons) {
        switch (DuoGlyphKindOf(view)) {
            case DuoGlyphKindBattery: if (!battery) battery = view; break;
            case DuoGlyphKindWifi: if (!wifi) wifi = view; break;
            case DuoGlyphKindCellular: if (!cell) cell = view; break;
            default: break;
        }
    }
    if (!battery) {
        // Some builds expose the trailing icons only as plain image views.
        for (UIView *view in icons.reverseObjectEnumerator) {
            if (DuoGlyphKindOf(view) == DuoGlyphKindBattery) { battery = view; break; }
            if (!battery) battery = view;
        }
    }
    if (!battery) { self.transitioning = NO; return; }

    // Capture the native glyphs while they are still on screen.
    UIImage *wifiImage = DuoGlyphImage(wifi);
    UIImage *cellImage = DuoGlyphImage(cell);

    UIView *host = bar;
    CGRect batteryFrame = [battery convertRect:battery.bounds toView:host];
    double scale = NativeNumber(@"OrbitScale", kEngine, 100.0) / 100.0;
    scale = MAX(0.50, MIN(1.50, scale));
    CGFloat height = MIN(34.0, MAX(30.0, host.bounds.size.height - 4)) * scale;
    CGFloat width = height * 32.0 / 34.0;
    CGFloat margin = 24.0;
    CGFloat x = MIN(host.bounds.size.width - width - margin, CGRectGetMaxX(batteryFrame) - width);
    x = MAX(8, x);
    CGFloat y = CGRectGetMidY(batteryFrame) - height / 2;
    y = MAX(1, MIN(y, host.bounds.size.height - height - 1));

    DuoGlyphView *ring = [[DuoGlyphView alloc] initWithFrame:CGRectMake(x, y, width, height)];
    ring.userInteractionEnabled = NO;
    ring.foreground = [self foregroundOf:bar];
    ring.showsPercent = NativeNumber(@"BatteryPercentageEnabled", kEngine, 1) != 0;
    ring.contentScale = NativeNumber(@"RightNetworkIconScale", kEngine, 47.0) / 100.0;
    [ring setNativeWifiImage:wifiImage];
    [ring setNativeCellularImage:cellImage];

    double level = [self doubleOf:battery key:@"chargePercent" fallback:80.0];
    if (level > 1.0) level /= 100.0;
    ring.charge = MAX(0, MIN(1, level));
    ring.charging = [self integerOf:battery key:@"chargingState" fallback:0] != 0;
    ring.lowPower = [self integerOf:battery key:@"saverModeActive" fallback:0] != 0;
    ring.wifiVisible = (wifi != nil);
    ring.wifiBars = wifi ? [self integerOf:wifi key:@"numberOfActiveBars" fallback:3] : 0;
    ring.cellularBars = cell ? [self integerOf:cell key:@"numberOfActiveBars" fallback:3] : 0;
    [host addSubview:ring];

    NSMutableDictionary *saved = [NSMutableDictionary dictionary];
    for (UIView *view in icons) {
        saved[[NSString stringWithFormat:@"%p", view]] = @{ @"view":view, @"hidden":@(view.hidden),
            @"alpha":@(view.alpha), @"center":[NSValue valueWithCGPoint:view.center],
            @"transform":[NSValue valueWithCGAffineTransform:view.transform] };
    }
    objc_setAssociatedObject(bar, &kRestoreKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(bar, &kRingKey, ring, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(bar, &kActiveKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [UIView animateWithDuration:0.75 delay:0 usingSpringWithDamping:0.86
        initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        for (UIView *view in icons) {
            view.center = ring.center;
            view.transform = CGAffineTransformMakeScale(0.12, 0.12);
            view.alpha = 0;
        }
        ring.alpha = 1;
    } completion:^(BOOL finished) {
        self.transitioning = NO;
        // Whether the spring finished or was interrupted, the glyphs end up
        // hidden; the maintain pass keeps them there from now on.
        for (UIView *view in icons) {
            view.hidden = YES;
            view.alpha = 0;
        }
    }];
}

#pragma mark - Tick

- (void)tick:(UIView *)bar {
    if (!bar || !bar.window) return;
    if (!NativeEngineEnabled() || NativeLocked() || NativeControlCenterVisible()) {
        [self unfold:bar];
        return;
    }
    if ([self isFolded:bar]) {
        UIView *ring = objc_getAssociatedObject(bar, &kRingKey);
        if (ring && ring.superview == bar) {
            [self maintain:bar];
            return;
        }
        // The bar was rebuilt and the ring went with it: fold again from scratch.
        objc_setAssociatedObject(bar, &kRestoreKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(bar, &kActiveKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        self.transitioning = NO;
    }
    if (self.transitioning) return;
    // Let the system render its real icons before animating anything.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
        (int64_t)(0.40 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (![self isFolded:bar] && !self.transitioning &&
            !NativeLocked() && !NativeControlCenterVisible()) [self fold:bar];
    });
}

- (void)scan {
    if (!NativeEngineEnabled() || NativeLocked() || NativeControlCenterVisible()) return;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden) continue;
            for (UIView *view in window.subviews) [self scanTree:view];
        }
    }
}

- (void)scanTree:(UIView *)view {
    if (!view) return;
    if ([NSStringFromClass(view.class) isEqualToString:@"STUIStatusBar"]) {
        [self tick:view];
        return;
    }
    NSString *className = NSStringFromClass(view.class);
    if ([className isEqualToString:@"STUIStatusBarImageView"] ||
        [className isEqualToString:@"STUIStatusBarStringView"] ||
        [className isEqualToString:@"STUIStatusBarBatteryView"]) {
        for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
            if ([NSStringFromClass(ancestor.class) isEqualToString:@"STUIStatusBar"]) {
                [self tick:ancestor];
                return;
            }
        }
    }
    if ([view isKindOfClass:UIScrollView.class]) {
        for (UIView *sub in view.subviews) [self scanTree:sub];
    }
}
@end

typedef void (*NativeVoidIMP)(id, SEL);

static NativeVoidIMP NativeOriginalStatusLayout;
static NativeVoidIMP NativeOriginalStatusWindow;
static NativeVoidIMP NativeOriginalStatusSuperview;
static NativeVoidIMP NativeOriginalImageWindow;
static NativeVoidIMP NativeOriginalImageSuperview;
static NativeVoidIMP NativeOriginalStringWindow;
static NativeVoidIMP NativeOriginalStringSuperview;

static UIView *NativeStatusBarForView(id object) {
    UIView *view = (UIView *)object;
    while (view) {
        if ([NSStringFromClass(view.class) isEqualToString:@"STUIStatusBar"]) return view;
        view = view.superview;
    }
    return nil;
}

static void NativeTickFromView(id object) {
    UIView *bar = NativeStatusBarForView(object);
    if (bar) [[NativeController shared] tick:bar];
}

static void NativeStatusLayout(id self, SEL _cmd) {
    if (NativeOriginalStatusLayout) NativeOriginalStatusLayout(self, _cmd);
    NativeTickFromView(self);
}

static void NativeStatusWindow(id self, SEL _cmd) {
    if (NativeOriginalStatusWindow) NativeOriginalStatusWindow(self, _cmd);
    NativeTickFromView(self);
}

static void NativeStatusSuperview(id self, SEL _cmd) {
    if (NativeOriginalStatusSuperview) NativeOriginalStatusSuperview(self, _cmd);
    NativeTickFromView(self);
}

static void NativeImageWindow(id self, SEL _cmd) {
    if (NativeOriginalImageWindow) NativeOriginalImageWindow(self, _cmd);
    NativeTickFromView(self);
}

static void NativeImageSuperview(id self, SEL _cmd) {
    if (NativeOriginalImageSuperview) NativeOriginalImageSuperview(self, _cmd);
    NativeTickFromView(self);
}

static void NativeStringWindow(id self, SEL _cmd) {
    if (NativeOriginalStringWindow) NativeOriginalStringWindow(self, _cmd);
    NativeTickFromView(self);
}

static void NativeStringSuperview(id self, SEL _cmd) {
    if (NativeOriginalStringSuperview) NativeOriginalStringSuperview(self, _cmd);
    NativeTickFromView(self);
}

// Add a class-local override when the selector is inherited. This avoids
// replacing UIView's implementation for every status-bar view in SpringBoard.
static IMP NativeInstallOneHook(NSString *className, SEL selector, IMP replacement) {
    Class cls = objc_getClass(className.UTF8String);
    if (!cls) return NULL;
    Method inheritedOrOwn = class_getInstanceMethod(cls, selector);
    if (!inheritedOrOwn) return NULL;
    IMP current = class_getMethodImplementation(cls, selector);
    if (current == replacement) return NULL;
    const char *types = method_getTypeEncoding(inheritedOrOwn);
    if (class_addMethod(cls, selector, replacement, types)) return current;
    Method own = class_getInstanceMethod(cls, selector);
    if (!own) return NULL;
    current = method_getImplementation(own);
    if (current == replacement) return NULL;
    method_setImplementation(own, replacement);
    return current;
}

static void NativeInstallHook(void) {
    IMP original = NativeInstallOneHook(@"STUIStatusBar", @selector(layoutSubviews), (IMP)NativeStatusLayout);
    if (original) NativeOriginalStatusLayout = (NativeVoidIMP)original;

    original = NativeInstallOneHook(@"STUIStatusBar", @selector(didMoveToWindow), (IMP)NativeStatusWindow);
    if (original) NativeOriginalStatusWindow = (NativeVoidIMP)original;
    original = NativeInstallOneHook(@"STUIStatusBar", @selector(didMoveToSuperview), (IMP)NativeStatusSuperview);
    if (original) NativeOriginalStatusSuperview = (NativeVoidIMP)original;

    // These callbacks cover glyphs that arrive after the bar's layout pass.
    original = NativeInstallOneHook(@"STUIStatusBarImageView", @selector(didMoveToWindow), (IMP)NativeImageWindow);
    if (original) NativeOriginalImageWindow = (NativeVoidIMP)original;
    original = NativeInstallOneHook(@"STUIStatusBarImageView", @selector(didMoveToSuperview), (IMP)NativeImageSuperview);
    if (original) NativeOriginalImageSuperview = (NativeVoidIMP)original;
    original = NativeInstallOneHook(@"STUIStatusBarStringView", @selector(didMoveToWindow), (IMP)NativeStringWindow);
    if (original) NativeOriginalStringWindow = (NativeVoidIMP)original;
    original = NativeInstallOneHook(@"STUIStatusBarStringView", @selector(didMoveToSuperview), (IMP)NativeStringSuperview);
    if (original) NativeOriginalStringSuperview = (NativeVoidIMP)original;
}

__attribute__((constructor)) static void NativeInit(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        for (double delay = 0.4; delay <= 6.0; delay += 0.6) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{ NativeInstallHook(); });
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                NativeInstallHook();
                [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(__unused NSTimer *t) {
                    [[NativeController shared] scan];
                }];
            });
    }
}
