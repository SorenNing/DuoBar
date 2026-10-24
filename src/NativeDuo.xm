#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "DuoGlyphView.h"

// No snapshot is taken anywhere. The visible UIKit views are transformed only
// after the real native icons have had time to settle.

static NSString *const kEngine = @"iya.banana.duoicon";
static NSString *const kGate = @"com.ning.duobar";
static NSString *const kBarKey = @"NativeDuo.Bar";
static NSString *const kRingKey = @"NativeDuo.Ring";
static NSString *const kActiveKey = @"NativeDuo.Active";
static NSString *const kRestoreKey = @"NativeDuo.Restore";

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

@interface NativeController : NSObject
@property(nonatomic) BOOL folded;
@property(nonatomic) BOOL transitioning;
@end

@implementation NativeController
+ (instancetype)shared {
    static NativeController *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [self new]; });
    return shared;
}

- (void)collect:(UIView *)view in:(NSMutableArray<UIView *> *)icons {
    NSString *name = NSStringFromClass(view.class);
    for (NSString *token in @[@"BatteryView", @"WifiSignalView", @"CellularSignalView"]) {
        if ([name containsString:token]) {
            [icons addObject:view];
            return;
        }
    }
    for (UIView *sub in view.subviews) [self collect:sub in:icons];
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

- (double)numberOf:(UIView *)view selector:(SEL)selector fallback:(double)fallback {
    if (![view respondsToSelector:selector]) return fallback;
    return ((double (*)(id, SEL))objc_msgSend)(view, selector);
}

- (void)unfold:(UIView *)bar {
    NSDictionary<NSString *, NSDictionary *> *saved = objc_getAssociatedObject(bar, &kRestoreKey);
    for (NSString *key in saved) {
        NSDictionary *info = saved[key];
        UIView *view = info[@"view"];
        view.hidden = [info[@"hidden"] boolValue];
        view.alpha = [info[@"alpha"] doubleValue];
        view.center = [info[@"center"] CGPointValue];
        view.transform = [info[@"transform"] CGAffineTransformValue];
    }
    [objc_getAssociatedObject(bar, &kRingKey) removeFromSuperview];
    objc_setAssociatedObject(bar, &kRingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(bar, &kRestoreKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(bar, &kActiveKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    self.folded = NO;
    self.transitioning = NO;
}

- (void)fold:(UIView *)bar {
    if (!bar || self.folded || self.transitioning) return;
    self.transitioning = YES;
    NSMutableArray<UIView *> *icons = [NSMutableArray array];
    [self collect:bar in:icons];
    if (icons.count == 0) { self.transitioning = NO; return; }

    UIView *battery = nil, *wifi = nil, *cell = nil;
    for (UIView *v in icons) {
        NSString *name = NSStringFromClass(v.class);
        if (!battery && [name containsString:@"BatteryView"]) battery = v;
        if (!wifi && [name containsString:@"WifiSignalView"]) wifi = v;
        if (!cell && [name containsString:@"CellularSignalView"]) cell = v;
    }
    if (!battery) { self.transitioning = NO; return; }

    // Do not convert or mutate geometry before this point: the real UIKit
    // hierarchy is the starting state, never a captured image.
    UIView *host = bar;
    CGRect b = [battery convertRect:battery.bounds toView:host];
    double scale = MAX(0.70, MIN(1.40, NativeNumber(@"SizeScale", kGate, 1.0)));
    CGFloat height = MIN(34.0, MAX(30.0, host.bounds.size.height - 4)) * scale;
    CGFloat width = height * 32.0 / 34.0;
    CGFloat margin = 24.0;
    CGFloat x = MIN(host.bounds.size.width - width - margin,
                    CGRectGetMaxX(b) - width);
    x = MAX(8, x);
    CGFloat y = CGRectGetMidY(b) - height / 2;
    y = MAX(1, MIN(y, host.bounds.size.height - height - 1));

    DuoGlyphView *ring = [[DuoGlyphView alloc] initWithFrame:CGRectMake(x, y, width, height)];
    ring.userInteractionEnabled = NO;
    ring.foreground = [self foregroundOf:bar];
    ring.showsPercent = NativeNumber(@"BatteryPercentageEnabled", kEngine, 1) != 0;
    double level = [self numberOf:battery selector:@selector(chargePercent) fallback:80.0];
    if (level > 1.0) level /= 100.0;
    ring.charge = MAX(0, MIN(1, level));
    ring.charging = [self numberOf:battery selector:@selector(chargingState) fallback:0] != 0;
    ring.lowPower = [self numberOf:battery selector:@selector(saverModeActive) fallback:0] != 0;
    ring.wifiVisible = wifi != nil;
    ring.wifiBars = wifi ? (NSInteger)[self numberOf:wifi selector:@selector(numberOfActiveBars) fallback:3] : 0;
    ring.cellularBars = cell ? (NSInteger)[self numberOf:cell selector:@selector(numberOfActiveBars) fallback:3] : 0;
    ring.alpha = 0;
    [host addSubview:ring];

    NSMutableDictionary *saved = [NSMutableDictionary dictionary];
    for (UIView *v in icons) {
        saved[@((unsigned long)v)] = @{ @"view":v, @"hidden":@(v.hidden),
            @"alpha":@(v.alpha), @"center":[NSValue valueWithCGPoint:v.center],
            @"transform":[NSValue valueWithCGAffineTransform:v.transform] };
    }
    objc_setAssociatedObject(bar, &kRestoreKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(bar, &kRingKey, ring, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(bar, &kActiveKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    self.folded = YES;

    [UIView animateWithDuration:0.75 delay:0 usingSpringWithDamping:0.86
        initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        for (UIView *v in icons) {
            v.center = ring.center;
            v.transform = CGAffineTransformMakeScale(0.12, 0.12);
            v.alpha = 0;
        }
        ring.alpha = 1;
        ring.reveal = 1;
    } completion:^(BOOL finished) {
        self.transitioning = NO;
        if (finished) for (UIView *v in icons) v.hidden = YES;
    }];
}

- (void)tick:(UIView *)bar {
    if (!bar || !bar.window) return;
    if (!NativeEngineEnabled() || NativeLocked() || NativeControlCenterVisible()) {
        [self unfold:bar];
        return;
    }
    if (!self.folded && !self.transitioning) {
        // Let the system render its real icons before animating anything.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
            (int64_t)(0.40 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!self.folded && !NativeLocked() && !NativeControlCenterVisible()) [self fold:bar];
        });
    }
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
    for (UIView *sub in view.subviews) [self scanTree:sub];
}
@end

static void (*NativeOriginalLayout)(id, SEL);
static void NativeLayout(id self, SEL _cmd) {
    if (NativeOriginalLayout) NativeOriginalLayout(self, _cmd);
    [[NativeController shared] tick:(UIView *)self];
}

static void NativeInstallHook(void) {
    Class cls = objc_getClass("STUIStatusBar");
    if (!cls) return;
    Method method = class_getInstanceMethod(cls, @selector(layoutSubviews));
    if (!method) return;
    IMP current = method_getImplementation(method);
    if (current == (IMP)NativeLayout) return;
    NativeOriginalLayout = (void (*)(id, SEL))current;
    method_setImplementation(method, (IMP)NativeLayout);
}

static void NativeImageAdded(const struct mach_header *header, intptr_t slide) {
    (void)header; (void)slide;
    dispatch_async(dispatch_get_main_queue(), ^{ NativeInstallHook(); });
}

__attribute__((constructor)) static void NativeInit(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        _dyld_register_func_for_add_image(NativeImageAdded);
            (void)h; (void)s;
            dispatch_async(dispatch_get_main_queue(), ^{ NativeInstallHook(); });
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                NativeInstallHook();
                [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(__unused NSTimer *t) {
                    [[NativeController shared] scan];
                }];
            });
    }
}
