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
@property(nonatomic,strong) NSMutableDictionary *nativeFrames;
@property(nonatomic,assign) BOOL folded;
@property(nonatomic,assign) BOOL busy;
@end

@implementation IDIStatusBarSession
+(instancetype)sessionForBar:(UIView *)bar {
    IDIStatusBarSession *session=objc_getAssociatedObject(bar,&IDISessionKey);
    if (!session) {
        session=[self new];
        session.nativeFrames=[NSMutableDictionary new];
        objc_setAssociatedObject(bar,&IDISessionKey,session,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return session;
}
-(instancetype)init {
    if ((self=[super init])) {
        _rightSurface=[[IDIRightSurface alloc] initWithFrame:CGRectZero];
        _controller=[[IDIStatusIconView alloc] initWithFrame:CGRectZero];
        _controller.state=self;
        _rightSurface.icon=_controller;
        [_rightSurface addSubview:_controller];
    }
    return self;
}
-(void)recordRightReturnEvent:(id)event details:(id)details {
    self.rightReturnTrace=@[event?:NSNull.null,details?:NSNull.null];
}
-(void)clearLeftTransitionTextMasks {
    self.leftTransitionTextMaskActive=NO;
    self.leftTransitionTextLabels=nil;
    self.leftTransitionCarrierLabels=nil;
}
-(void)dealloc { [self clearLeftTransitionTextMasks]; }

-(void)findIconsIn:(UIView *)view into:(NSMutableArray<UIView *> *)icons {
    if (!view) return;
    NSString *name=NSStringFromClass(view.class);
    if ([name containsString:@"BatteryView"]) { self.battery=view; [icons addObject:view]; }
    else if ([name containsString:@"WifiSignalView"]) { self.wifi=view; [icons addObject:view]; }
    else if ([name containsString:@"CellularSignalView"]) { self.cellular=view; [icons addObject:view]; }
    else {
        for (UIView *sub in view.subviews) [self findIconsIn:sub into:icons];
    }
}
-(void)restore {
    for (NSValue *key in self.nativeFrames) {
        UIView *view=key.nonretainedObjectValue;
        NSDictionary *info=self.nativeFrames[key];
        view.hidden=[info[@"hidden"] boolValue];
        view.alpha=[info[@"alpha"] doubleValue];
        view.transform=CGAffineTransformIdentity;
        view.center=[info[@"center"] CGPointValue];
    }
    [self.nativeFrames removeAllObjects];
    self.folded=NO;
}
-(void)attachToBar:(UIView *)bar {
    if (!bar.window || self.folded) return;
    if (!IDIPrefBool("Enabled",YES)) { [self.rightSurface removeFromSuperview]; return; }
    if (!IDIPrefBool("RightUnlockAnimation",YES) && !IDIPrefBool("RightControlCenterReturnAnimation",YES)) {
        [self.rightSurface removeFromSuperview]; return;
    }
    UIView *foreground=[bar valueForKey:@"foregroundView"];
    if (![foreground isKindOfClass:UIView.class]) {
        // iOS 17 keeps the trailing cluster directly on the bar; fall back to the
        // bar itself so the ring is still hosted when foregroundView is absent.
        foreground=bar;
    }
    [foreground addSubview:self.rightSurface];
    self.rightSurface.frame=foreground.bounds;
    [self.rightSurface layoutIfNeeded];
    NSMutableArray<UIView *> *icons=[NSMutableArray array];
    [self findIconsIn:foreground into:icons];
    if (!self.battery || icons.count==0) return;
    UIView *anchor=self.battery.superview?:foreground;
    CGRect anchorFrame=[anchor convertRect:anchor.bounds toView:foreground];
    double scale=IDIPrefDouble("OrbitScale",100)/100.0;
    scale=MAX(0.5,MIN(1.5,scale));
    CGFloat h=MAX(28,MIN(42,foreground.bounds.size.height-4))*scale;
    CGFloat w=h*32.0/34.0;
    CGFloat x=MIN(foreground.bounds.size.width-w-6,
                  MAX(0,CGRectGetMaxX(anchorFrame)-w+IDIPrefDouble("OrbitXOffset",0)));
    CGFloat y=MAX(0,CGRectGetMidY(anchorFrame)-h/2+IDIPrefDouble("OrbitYOffset",0));
    self.controller.frame=CGRectMake(x,y,w,h);
    self.controller.hidden=NO;
    [self.controller refreshFromBattery:self.battery wifi:self.wifi cell:self.cellular];
    self.folded=YES;
    if (!self.busy) {
        self.busy=YES;
        for (UIView *icon in icons) {
            self.nativeFrames[@((NSUInteger)icon)]=@{@"hidden":@(icon.hidden),@"alpha":@(icon.alpha),@"center":[NSValue valueWithCGPoint:icon.center]};
        }
        [UIView animateWithDuration:0.65 delay:0.4 usingSpringWithDamping:.86 initialSpringVelocity:0
          options:UIViewAnimationOptionCurveEaseOut animations:^{
            for (UIView *icon in icons) {
                icon.center=self.controller.center;
                icon.transform=CGAffineTransformMakeScale(.12,.12);
                icon.alpha=0;
            }
        } completion:^(BOOL done){
            self.busy=NO;
            if (done) for (UIView *icon in icons) icon.hidden=YES;
        }];
    }
}
@end
