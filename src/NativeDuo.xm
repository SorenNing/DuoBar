#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>

// NativeDuo: no snapshots. Actual system icon views are moved on the main thread.

static NSString *const kEngineDomain = @"iya.banana.duoicon";
static NSString *const kGateDomain = @"com.ning.duobar";

static CFPropertyListRef Copy(NSString *k, NSString *domain) {
    return CFPreferencesCopyValue((__bridge CFStringRef)k, (__bridge CFStringRef)domain,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
static double Dbl(NSString *k, double fallback) {
    CFPropertyListRef v = Copy(k, kGateDomain);
    double r = fallback;
    if (v) {
        if (CFGetTypeID(v) == CFNumberGetTypeID()) r = [(__bridge NSNumber *)v doubleValue];
        else if (CFGetTypeID(v) == CFBooleanGetTypeID()) r = CFBooleanGetValue((CFBooleanRef)v) ? 1 : 0;
        CFRelease(v);
    }
    return r;
}
static BOOL Bool(NSString *k, BOOL fallback) { return Dbl(k, fallback) != 0; }
static double EDbl(NSString *k, double fallback) {
    CFPropertyListRef v = Copy(k, kEngineDomain);
    double r = fallback;
    if (v) {
        if (CFGetTypeID(v) == CFNumberGetTypeID()) r = [(__bridge NSNumber *)v doubleValue];
        else if (CFGetTypeID(v) == CFBooleanGetTypeID()) r = CFBooleanGetValue((CFBooleanRef)v) ? 1 : 0;
        CFRelease(v);
    }
    return r;
}

static BOOL CoverSheet(void) {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows)
            if ([[NSStringFromClass(w.class) lowercaseString] containsString:@"coversheet"] && !w.hidden && w.alpha > .01)
                return YES;
    }
    return NO;
}

static BOOL Locked(void) {
    Class c = NSClassFromString(@"SBLockScreenManager");
    SEL sh = NSSelectorFromString(@"sharedInstance");
    if (!c || ![c respondsToSelector:sh]) return NO;
    id m = ((id (*)(id,SEL))objc_msgSend)(c,sh);
    for (NSString *n in @[@"isUILocked", @"isLockScreenVisible"]) {
        SEL s = NSSelectorFromString(n);
        if ([m respondsToSelector:s] && ((BOOL(*)(id,SEL))objc_msgSend)(m,s)) return YES;
    }
    return NO;
}

@interface NativeDuoRing : UIView
@property(nonatomic,strong) UIColor *fg;
@property(nonatomic,strong) UIColor *accent;
@property(nonatomic) double level;
@property(nonatomic) double progress;
@property(nonatomic) BOOL percent;
@property(nonatomic) BOOL wifi;
@end

@implementation NativeDuoRing
- (instancetype)initWithFrame:(CGRect)f {
    if ((self=[super initWithFrame:f])) {
        _fg=UIColor.labelColor; _accent=[UIColor colorWithRed:.204 green:.80 blue:.348 alpha:1];
        _level=1; _percent=YES; _wifi=YES;
        self.opaque=NO; self.backgroundColor=UIColor.clearColor;
    }
    return self;
}
- (void)drawRect:(CGRect)rect {
    CGContextRef c=UIGraphicsGetCurrentContext();
    CGFloat w=self.bounds.size.width,h=self.bounds.size.height;
    CGFloat s=MIN(w/34,h/34),cx=w/2,cy=h/2,r=12*s,lw=2*s;
    double p=MAX(0,MIN(1,_progress));
    CGContextSetLineWidth(c,lw);
    CGContextSetLineCap(c,kCGLineCapRound);
    UIColor *base=[_fg colorWithAlphaComponent:.22*p];
    CGContextSetStrokeColorWithColor(c,base.CGColor);
    CGContextAddArc(c,cx,cy,r,-M_PI_2,3*M_PI_2,0); CGContextStrokePath(c);
    UIColor *fill=(_level<.20?[UIColor systemRedColor]:_accent);
    CGContextSetStrokeColorWithColor(c,fill.CGColor);
    CGContextAddArc(c,cx,cy,r,-M_PI_2,-M_PI_2+2*M_PI*_level*p,0);
    CGContextStrokePath(c);
    if (_wifi && p>.6) {
        UIColor *col=[_fg colorWithAlphaComponent:p];
        for (int i=0;i<3;i++) {
            CGFloat rr=(4.5+i*3.1)*s;
            CGContextSetStrokeColorWithColor(c,col.CGColor);
            CGContextSetLineWidth(c,1.65*s);
            CGContextAddArc(c,cx,cy+2.8*s,rr,-M_PI_2-.60,-M_PI_2+.60,0);
            CGContextStrokePath(c);
        }
        CGContextSetFillColorWithColor(c,col.CGColor);
        CGContextFillEllipseInRect(c,CGRectMake(cx-1.25*s,cy+7*s,2.5*s,2.5*s));
    }
    if (_percent && p>.35) {
        NSString *t=[NSString stringWithFormat:@"%ld%%",(long)lround(_level*100)];
        NSMutableParagraphStyle *ps=[NSMutableParagraphStyle new]; ps.alignment=NSTextAlignmentCenter;
        UIFont *f=[UIFont monospacedDigitSystemFontOfSize:7*s weight:UIFontWeightSemibold];
        UIColor *col=[_fg colorWithAlphaComponent:MIN(1,(p-.35)/.5)];
        [t drawInRect:CGRectMake(cx-r,cy-5.5*s,2*r,9*s) withAttributes:@{
            NSFontAttributeName:f,NSForegroundColorAttributeName:col,NSParagraphStyleAttributeName:ps}];
    }
}
@end

@interface NativeDuo : NSObject
@property(nonatomic,strong) NativeDuoRing *ring;
@property(nonatomic,strong) NSMutableArray<UIView *> *icons;
@property(nonatomic,strong) NSValue *savedFrame;
@property(nonatomic,weak) UIView *battery;
@property(nonatomic,strong) UIColor *oldTint;
@property(nonatomic) BOOL folded;
@property(nonatomic) BOOL animating;
@end

@implementation NativeDuo
+ (instancetype)shared {
    static NativeDuo *x; static dispatch_once_t o;
    dispatch_once(&o,^{x=[self new]; x.icons=[NSMutableArray array];});
    return x;
}
- (void)restore {
    if (!_folded) return;
    _folded=NO; _animating=NO;
    for (UIView *v in _icons) { v.hidden=NO; v.alpha=1; v.transform=CGAffineTransformIdentity; }
    [_icons removeAllObjects];
    if (_battery) _battery.tintColor=_oldTint;
    [_ring removeFromSuperview]; _ring=nil;
}
- (void)collectIcons:(UIView *)v into:(NSMutableArray<UIView *> *)found battery:(UIView **)battery classes:(NSArray<NSString *> *)classes {
    if (!v) return;
    for (NSString *n in classes) {
        Class c=NSClassFromString(n);
        if (c && [v isKindOfClass:c]) { [found addObject:v]; if (!*battery) *battery=v; }
    }
    for (UIView *sv in v.subviews) [self collectIcons:sv into:found battery:battery classes:classes];
}

- (void)scanBar:(UIView *)v {
    if (!v) return;
    if ([NSStringFromClass(v.class) isEqualToString:@"STUIStatusBar"]) { [self fold:v]; return; }
    for (UIView *sv in v.subviews) [self scanBar:sv];
}

- (void)fold:(UIView *)bar {
    if (_folded || _animating) return;
    _animating=YES;
    [self restore];
    NSMutableArray<UIView *> *found=[NSMutableArray array];
    UIView *battery=nil;
    NSArray<NSString *> *classes=@[@"STUIStatusBarBatteryView",@"STUIStatusBarWifiSignalView",
      @"STUIStatusBarCellularSignalView",@"STUIStatusBarSignalView",@"_UIBatteryView",
      @"_UIStatusBarWifiSignalView",@"_UIStatusBarSignalView"];
    [self collectIcons:bar into:found battery:&battery classes:classes];
    if (!battery) { _animating=NO; return; }
    _battery=battery;
    _oldTint=battery.tintColor;
    UIColor *fg=[bar valueForKey:@"foregroundColor"];
    if (![fg isKindOfClass:UIColor.class]) fg=battery.tintColor;
    if (!fg) fg=UIColor.labelColor;
    CGRect b=[battery.superview convertRect:battery.frame toView:bar];
    CGFloat h=MAX(30,MIN(36,b.size.height+8));
    NativeDuoRing *ring=[[NativeDuoRing alloc] initWithFrame:CGRectMake(b.origin.x-12,b.origin.y-4,h+10,h)];
    ring.fg=fg; ring.percent=(EDbl(@"BatteryPercentageEnabled",1)!=0);
    ring.wifi=(found.count>1);
    ring.progress=0;
    double lvl=[battery respondsToSelector:@selector(chargePercent)] ? ((double (*)(id,SEL))objc_msgSend)(battery,@selector(chargePercent))/100.0 : .8;
    if (lvl<=0 || lvl>1) lvl=.8;
    ring.level=lvl;
    [bar addSubview:ring];
    _ring=ring;
    _icons=found;
    // Capture the actual on-screen geometry only now. No snapshot is made.
    // Keep the originals visible while the native display was on screen; animate
    // each original view's actual transform instead of replacing it.
    CGFloat dx=ring.center.x-battery.center.x;
    CGFloat dy=ring.center.y-battery.center.y;
    battery.tintColor=fg;
    _folded=YES;
    [UIView animateWithDuration:0.65 delay:0 usingSpringWithDamping:.84 initialSpringVelocity:0
      options:UIViewAnimationOptionCurveEaseOut animations:^{
        for (UIView *v in found) {
            v.transform=CGAffineTransformMakeScale(.08,.08);
            v.center=CGPointMake(ring.center.x,ring.center.y);
            v.alpha=0;
        }
        ring.progress=1;
        [ring setNeedsDisplay];
      } completion:^(BOOL done){
        if (!done) { self->_animating=NO; [self restore]; return; }
        for (UIView *v in found) v.hidden=YES;
        self->_animating=NO;
    }];
}
- (void)tick {
    @try {
        if (_folded) return;
        if (Locked() || CoverSheet()) { [self restore]; return; }
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if (![s isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *w in ((UIWindowScene *)s).windows) {
                if (w.hidden) continue;
                            [self scanBar:w];<QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>

// NativeDuo: no snapshots. Actual system icon views are moved on the main thread.

static NSString *const kEngineDomain = @"iya.banana.duoicon";
static NSString *const kGateDomain = @"com.ning.duobar";

static CFPropertyListRef Copy(NSString *k, NSString *domain) {
    return CFPreferencesCopyValue((__bridge CFStringRef)k, (__bridge CFStringRef)domain,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
static double Dbl(NSString *k, double fallback) {
    CFPropertyListRef v = Copy(k, kGateDomain);
    double r = fallback;
    if (v) {
        if (CFGetTypeID(v) == CFNumberGetTypeID()) r = [(__bridge NSNumber *)v doubleValue];
        else if (CFGetTypeID(v) == CFBooleanGetTypeID()) r = CFBooleanGetValue((CFBooleanRef)v) ? 1 : 0;
        CFRelease(v);
    }
    return r;
}
static BOOL Bool(NSString *k, BOOL fallback) { return Dbl(k, fallback) != 0; }
static double EDbl(NSString *k, double fallback) {
    CFPropertyListRef v = Copy(k, kEngineDomain);
    double r = fallback;
    if (v) {
        if (CFGetTypeID(v) == CFNumberGetTypeID()) r = [(__bridge NSNumber *)v doubleValue];
        else if (CFGetTypeID(v) == CFBooleanGetTypeID()) r = CFBooleanGetValue((CFBooleanRef)v) ? 1 : 0;
        CFRelease(v);
    }
    return r;
}

static BOOL CoverSheet(void) {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows)
            if ([[NSStringFromClass(w.class) lowercaseString] containsString:@"coversheet"] && !w.hidden && w.alpha > .01)
                return YES;
    }
    return NO;
}

static BOOL Locked(void) {
    Class c = NSClassFromString(@"SBLockScreenManager");
    SEL sh = NSSelectorFromString(@"sharedInstance");
    if (!c || ![c respondsToSelector:sh]) return NO;
    id m = ((id (*)(id,SEL))objc_msgSend)(c,sh);
    for (NSString *n in @[@"isUILocked", @"isLockScreenVisible"]) {
        SEL s = NSSelectorFromString(n);
        if ([m respondsToSelector:s] && ((BOOL(*)(id,SEL))objc_msgSend)(m,s)) return YES;
    }
    return NO;
}

@interface NativeDuoRing : UIView
@property(nonatomic,strong) UIColor *fg;
@property(nonatomic,strong) UIColor *accent;
@property(nonatomic) double level;
@property(nonatomic) double progress;
@property(nonatomic) BOOL percent;
@property(nonatomic) BOOL wifi;
@end

@implementation NativeDuoRing
- (instancetype)initWithFrame:(CGRect)f {
    if ((self=[super initWithFrame:f])) {
        _fg=UIColor.labelColor; _accent=[UIColor colorWithRed:.204 green:.80 blue:.348 alpha:1];
        _level=1; _percent=YES; _wifi=YES;
        self.opaque=NO; self.backgroundColor=UIColor.clearColor;
    }
    return self;
}
- (void)drawRect:(CGRect)rect {
    CGContextRef c=UIGraphicsGetCurrentContext();
    CGFloat w=self.bounds.size.width,h=self.bounds.size.height;
    CGFloat s=MIN(w/34,h/34),cx=w/2,cy=h/2,r=12*s,lw=2*s;
    double p=MAX(0,MIN(1,_progress));
    CGContextSetLineWidth(c,lw);
    CGContextSetLineCap(c,kCGLineCapRound);
    UIColor *base=[_fg colorWithAlphaComponent:.22*p];
    CGContextSetStrokeColorWithColor(c,base.CGColor);
    CGContextAddArc(c,cx,cy,r,-M_PI_2,3*M_PI_2,0); CGContextStrokePath(c);
    UIColor *fill=(_level<.20?[UIColor systemRedColor]:_accent);
    CGContextSetStrokeColorWithColor(c,fill.CGColor);
    CGContextAddArc(c,cx,cy,r,-M_PI_2,-M_PI_2+2*M_PI*_level*p,0);
    CGContextStrokePath(c);
    if (_wifi && p>.6) {
        UIColor *col=[_fg colorWithAlphaComponent:p];
        for (int i=0;i<3;i++) {
            CGFloat rr=(4.5+i*3.1)*s;
            CGContextSetStrokeColorWithColor(c,col.CGColor);
            CGContextSetLineWidth(c,1.65*s);
            CGContextAddArc(c,cx,cy+2.8*s,rr,-M_PI_2-.60,-M_PI_2+.60,0);
            CGContextStrokePath(c);
        }
        CGContextSetFillColorWithColor(c,col.CGColor);
        CGContextFillEllipseInRect(c,CGRectMake(cx-1.25*s,cy+7*s,2.5*s,2.5*s));
    }
    if (_percent && p>.35) {
        NSString *t=[NSString stringWithFormat:@"%ld%%",(long)lround(_level*100)];
        NSMutableParagraphStyle *ps=[NSMutableParagraphStyle new]; ps.alignment=NSTextAlignmentCenter;
        UIFont *f=[UIFont monospacedDigitSystemFontOfSize:7*s weight:UIFontWeightSemibold];
        UIColor *col=[_fg colorWithAlphaComponent:MIN(1,(p-.35)/.5)];
        [t drawInRect:CGRectMake(cx-r,cy-5.5*s,2*r,9*s) withAttributes:@{
            NSFontAttributeName:f,NSForegroundColorAttributeName:col,NSParagraphStyleAttributeName:ps}];
    }
}
@end

@interface NativeDuo : NSObject
@property(nonatomic,strong) NativeDuoRing *ring;
@property(nonatomic,strong) NSMutableArray<UIView *> *icons;
@property(nonatomic,strong) NSValue *savedFrame;
@property(nonatomic,weak) UIView *battery;
@property(nonatomic,strong) UIColor *oldTint;
@property(nonatomic) BOOL folded;
@property(nonatomic) BOOL animating;
@end

@implementation NativeDuo
+ (instancetype)shared {
    static NativeDuo *x; static dispatch_once_t o;
    dispatch_once(&o,^{x=[self new]; x.icons=[NSMutableArray array];});
    return x;
}
- (void)restore {
    if (!_folded) return;
    _folded=NO; _animating=NO;
    for (UIView *v in _icons) { v.hidden=NO; v.alpha=1; v.transform=CGAffineTransformIdentity; }
    [_icons removeAllObjects];
    if (_battery) _battery.tintColor=_oldTint;
    [_ring removeFromSuperview]; _ring=nil;
}
- (void)collectIcons:(UIView *)v into:(NSMutableArray<UIView *> *)found battery:(UIView **)battery classes:(NSArray<NSString *> *)classes {
    if (!v) return;
    for (NSString *n in classes) {
        Class c=NSClassFromString(n);
        if (c && [v isKindOfClass:c]) { [found addObject:v]; if (!*battery) *battery=v; }
    }
    for (UIView *sv in v.subviews) [self collectIcons:sv into:found battery:battery classes:classes];
}

- (void)scanBar:(UIView *)v {
    if (!v) return;
    if ([NSStringFromClass(v.class) isEqualToString:@"STUIStatusBar"]) { [self fold:v]; return; }
    for (UIView *sv in v.subviews) [self scanBar:sv];
}

- (void)fold:(UIView *)bar {
    if (_folded || _animating) return;
    _animating=YES;
    [self restore];
    NSMutableArray<UIView *> *found=[NSMutableArray array];
    UIView *battery=nil;
    NSArray<NSString *> *classes=@[@"STUIStatusBarBatteryView",@"STUIStatusBarWifiSignalView",
      @"STUIStatusBarCellularSignalView",@"STUIStatusBarSignalView",@"_UIBatteryView",
      @"_UIStatusBarWifiSignalView",@"_UIStatusBarSignalView"];
    [self collectIcons:bar into:found battery:&battery classes:classes];
    if (!battery) { _animating=NO; return; }
    _battery=battery;
    _oldTint=battery.tintColor;
    UIColor *fg=[bar valueForKey:@"foregroundColor"];
    if (![fg isKindOfClass:UIColor.class]) fg=battery.tintColor;
    if (!fg) fg=UIColor.labelColor;
    CGRect b=[battery.superview convertRect:battery.frame toView:bar];
    CGFloat h=MAX(30,MIN(36,b.size.height+8));
    NativeDuoRing *ring=[[NativeDuoRing alloc] initWithFrame:CGRectMake(b.origin.x-12,b.origin.y-4,h+10,h)];
    ring.fg=fg; ring.percent=(EDbl(@"BatteryPercentageEnabled",1)!=0);
    ring.wifi=(found.count>1);
    ring.progress=0;
    double lvl=[battery respondsToSelector:@selector(chargePercent)] ? ((double (*)(id,SEL))objc_msgSend)(battery,@selector(chargePercent))/100.0 : .8;
    if (lvl<=0 || lvl>1) lvl=.8;
    ring.level=lvl;
    [bar addSubview:ring];
    _ring=ring;
    _icons=found;
    // Capture the actual on-screen geometry only now. No snapshot is made.
    // Keep the originals visible while the native display was on screen; animate
    // each original view's actual transform instead of replacing it.
    CGFloat dx=ring.center.x-battery.center.x;
    CGFloat dy=ring.center.y-battery.center.y;
    battery.tintColor=fg;
    _folded=YES;
    [UIView animateWithDuration:0.65 delay:0 usingSpringWithDamping:.84 initialSpringVelocity:0
      options:UIViewAnimationOptionCurveEaseOut animations:^{
        for (UIView *v in found) {
            v.transform=CGAffineTransformMakeScale(.08,.08);
            v.center=CGPointMake(ring.center.x,ring.center.y);
            v.alpha=0;
        }
        ring.progress=1;
        [ring setNeedsDisplay];
      } completion:^(BOOL done){
        if (!done) { self->_animating=NO; [self restore]; return; }
        for (UIView *v in found) v.hidden=YES;
        self->_animating=NO;
    }];
}
- (void)tick {
    @try {
        if (_folded) return;
        if (Locked() || CoverSheet()) { [self restore]; return; }
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if (![s isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *w in ((UIWindowScene *)s).windows) {
                if (w.hidden) continue;
                void (^unusedWalk)(UIView*)=^(UIView *v){
                    if (!v) return;
                    if ([NSStringFromClass(v.class) isEqualToString:@"STUIStatusBar"]) { [self fold:v]; return; }
                    for (UIView *sv in v.subviews) walk(sv);
                };
                walk(w);
            }
        }
    } @catch (__unused NSException *e) {
        _animating=NO;
    }
}
@end

static void (*origLayout)(id,SEL);
static void NewLayout(id self,SEL _cmd) {
    origLayout(self,_cmd);
    [[NativeDuo shared] tick];
}

static void Start(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    Class c=NSClassFromString(@"STUIStatusBar");
    Method m=c?class_getInstanceMethod(c,@selector(layoutSubviews)):NULL;
    if (m) {
        origLayout=(void (*)(id,SEL))method_getImplementation(m);
        method_setImplementation(m,(IMP)NewLayout);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.2*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        [NSTimer scheduledTimerWithTimeInterval:.5 repeats:YES block:^(__unused NSTimer *t){ [[NativeDuo shared] tick]; }];
    });
}

__attribute__((constructor)) static void Init(void) { Start(); }
