#import "IDIStatusBarSession.h"
#import "IDIRightSurface.h"
#import "IDIStatusIconView.h"
#import "IDICompat.h"
#import <objc/runtime.h>
#import <objc/message.h>

static char IDISessionKey;

@interface IDIStatusBarSession ()
@property(nonatomic,weak) UIView *battery;
@property(nonatomic,weak) UIView *wifi;
@property(nonatomic,weak) UIView *cellular;
@property(nonatomic,strong) NSMutableDictionary<NSValue *, NSDictionary *> *nativeFrames;
@property(nonatomic,assign) BOOL folded;
@property(nonatomic,assign) BOOL busy;
@property(nonatomic,assign) BOOL attaching;
@property(nonatomic,assign) BOOL attachQueued;
-(void)attachNow:(UIView *)bar;
@end

@implementation IDIStatusBarSession
+(instancetype)sessionForBar:(UIView *)bar {
    IDIStatusBarSession *session = objc_getAssociatedObject(bar, &IDISessionKey);
    if (!session) {
        session = [self new];
        session.nativeFrames = [NSMutableDictionary new];
        objc_setAssociatedObject(bar, &IDISessionKey, session, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return session;
}
-(instancetype)init {
    if ((self = [super init])) {
        _rightSurface = [[IDIRightSurface alloc] initWithFrame:CGRectZero];
        _controller = [[IDIStatusIconView alloc] initWithFrame:CGRectZero];
        _controller.state = self;
        _rightSurface.icon = _controller;
        [_rightSurface addSubview:_controller];
    }
    return self;
}
-(void)recordRightReturnEvent:(id)event details:(id)details {
    self.rightReturnTrace = @[event ?: NSNull.null, details ?: NSNull.null];
}
-(void)clearLeftTransitionTextMasks {
    self.leftTransitionTextMaskActive = NO;
    self.leftTransitionTextLabels = nil;
    self.leftTransitionCarrierLabels = nil;
}
-(void)dealloc { [self clearLeftTransitionTextMasks]; }

-(void)findIconsIn:(UIView *)view into:(NSMutableArray<UIView *> *)icons {
    if (!view) return;
    NSString *name = NSStringFromClass(view.class);
    if ([name containsString:@"BatteryView"]) { self.battery = view; [icons addObject:view]; }
    else if ([name containsString:@"WifiSignalView"]) { self.wifi = view; [icons addObject:view]; }
    else if ([name containsString:@"CellularSignalView"]) { self.cellular = view; [icons addObject:view]; }
    else {
        for (UIView *sub in view.subviews) [self findIconsIn:sub into:icons];
    }
}
-(void)restore {
    @try {
        for (NSValue *key in self.nativeFrames.allKeys) {
            UIView *view = key.nonretainedObjectValue;
            NSDictionary *info = self.nativeFrames[key];
            if (!view) continue;
            view.hidden = [info[@"hidden"] boolValue];
            view.alpha = [info[@"alpha"] doubleValue];
            view.transform = CGAffineTransformIdentity;
            view.center = [info[@"center"] CGPointValue];
        }
        [self.nativeFrames removeAllObjects];
    } @catch (__unused NSException *e) {}
    self.folded = NO;
}

// Adding subviews from inside layoutSubviews re-enters the bar's layout and can
// recurse until the stack overflows, so the whole attach runs on the next
// runloop turn and is guarded against re-entry.
-(void)attachToBar:(UIView *)bar {
    if (self.folded || self.attaching || self.attachQueued) return;
    if (!bar.window) return;
    if (!IDIPrefBool("Enabled", YES)) { [self.rightSurface removeFromSuperview]; return; }
    if (!IDIPrefBool("RightUnlockAnimation", YES) && !IDIPrefBool("RightControlCenterReturnAnimation", YES)) {
        [self.rightSurface removeFromSuperview];
        return;
    }
    self.attachQueued = YES;
    __weak typeof(self) weakSelf = self;
    __weak UIView *weakBar = bar;
    dispatch_async(dispatch_get_main_queue(), ^{
        IDIStatusBarSession *self_ = weakSelf;
        UIView *bar_ = weakBar;
        if (!self_) return;
        self_.attachQueued = NO;
        if (!bar_ || !bar_.window || self_.folded) return;
        self_.attaching = YES;
        @try {
            [self_ attachNow:bar_];
        } @catch (__unused NSException *e) {
            [self_.rightSurface removeFromSuperview];
            self_.folded = NO;
        }
        self_.attaching = NO;
    });
}

-(void)attachNow:(UIView *)bar {
    UIView *foreground = nil;
    @try { foreground = [bar valueForKey:@"foregroundView"]; } @catch (__unused NSException *e) {}
    if (![foreground isKindOfClass:UIView.class]) foreground = bar;

    [foreground addSubview:self.rightSurface];
    self.rightSurface.frame = foreground.bounds;
    [self.rightSurface layoutIfNeeded];

    self.battery = nil; self.wifi = nil; self.cellular = nil;
    NSMutableArray<UIView *> *icons = [NSMutableArray array];
    [self findIconsIn:foreground into:icons];
    if (icons.count == 0) {
        [self.rightSurface removeFromSuperview];
        return;
    }

    UIView *anchor = self.battery.superview ?: foreground;
    CGRect anchorFrame = [anchor convertRect:anchor.bounds toView:foreground];
    double scale = IDIPrefDouble("OrbitScale", 100) / 100.0;
    scale = MAX(0.5, MIN(1.5, scale));
    CGFloat h = MAX(28, MIN(42, foreground.bounds.size.height - 4)) * scale;
    CGFloat w = h * 32.0 / 34.0;
    CGFloat x = MIN(foreground.bounds.size.width - w - 6,
                    MAX(0, CGRectGetMaxX(anchorFrame) - w + IDIPrefDouble("OrbitXOffset", 0)));
    CGFloat y = MAX(0, CGRectGetMidY(anchorFrame) - h / 2 + IDIPrefDouble("OrbitYOffset", 0));
    self.controller.frame = CGRectMake(x, y, w, h);

    @try {
        UIColor *fg = nil;
        NSDictionary *attrs = [bar valueForKey:@"styleAttributes"];
        if ([attrs isKindOfClass:NSDictionary.class]) fg = attrs[@"textColor"] ?: attrs[@"imageTintColor"];
        if (![fg isKindOfClass:UIColor.class]) fg = [bar valueForKey:@"foregroundColor"];
        if (![fg isKindOfClass:UIColor.class]) fg = UIColor.labelColor;
        [self.controller setForeground:fg];
        [self.controller refreshFromBattery:self.battery wifi:self.wifi cell:self.cellular];
    } @catch (__unused NSException *e) {}

    self.folded = YES;
    if (self.busy) return;
    self.busy = YES;

    for (UIView *icon in icons) {
        self.nativeFrames[(id)[NSValue valueWithNonretainedObject:icon]] =
            @{@"hidden": @(icon.hidden), @"alpha": @(icon.alpha),
              @"center": [NSValue valueWithCGPoint:icon.center]};
    }
    CGPoint target = self.controller.center;
    [UIView animateWithDuration:0.65 delay:0.4 usingSpringWithDamping:.86 initialSpringVelocity:0
        options:UIViewAnimationOptionCurveEaseOut animations:^{
            for (UIView *icon in icons) {
                icon.center = target;
                icon.transform = CGAffineTransformMakeScale(.12, .12);
                icon.alpha = 0;
            }
        } completion:^(BOOL done) {
            self.busy = NO;
            if (done) for (UIView *icon in icons) icon.hidden = YES;
        }];
}
@end
