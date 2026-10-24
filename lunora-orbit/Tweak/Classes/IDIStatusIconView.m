#import "IDIStatusIconView.h"
#import "DuoGlyphView.h"
#import <objc/message.h>

@implementation IDIStatusIconView
@synthesize duoGlyph=_duoGlyph;
-(instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.opaque=NO;
        self.backgroundColor=UIColor.clearColor;
        self.contentMode=UIViewContentModeRedraw;
        _duoGlyph=[[DuoGlyphView alloc] initWithFrame:self.bounds];
        _duoGlyph.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [self addSubview:_duoGlyph];
    }
    return self;
}
-(void)layoutSubviews { [super layoutSubviews]; self.duoGlyph.frame=self.bounds; }
-(BOOL)isVisibleForInteraction { return self.window && !self.hidden && self.alpha>0.01; }
-(BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e {
    return self.isVisibleForInteraction && [super pointInside:p withEvent:e];
}
-(id)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    id hit=[super hitTest:p withEvent:e];
    return hit==self?nil:hit;
}
-(BOOL)preservesMikkyyCompatibility { return NO; }
-(void)restoreMikkyyCompatibility { self.alpha=1; }
-(BOOL)duoRevealSuppressed { return NO; }
-(double)rawRevealProgress { return 1.0; }
-(double)morphProgressForRaw:(double)p { return MAX(0,MIN(1,p)); }
-(BOOL)revealTemporarily { return !self.duoRevealSuppressed; }
-(BOOL)canContinueNativePresentation { return self.isVisibleForInteraction; }
-(void)prepareOrbitAlignment { [self setNeedsLayout]; }
-(void)updateOrbitAlignment { [self setNeedsLayout]; }
-(void)prepareLayoutForOrbitAlignment { [self setNeedsLayout]; }
-(BOOL)wantsAnimatedNativeHandoff { return YES; }
-(BOOL)usesStagedOrbitSignals { return YES; }
-(BOOL)prefersBaselineAlignment { return NO; }
-(BOOL)prefersCenterVerticalAlignment { return YES; }
-(BOOL)wantsCrossfade { return YES; }
-(void)didTap:(UITapGestureRecognizer *)gesture {
    [self.state recordRightReturnEvent:gesture details:nil];
}
-(void)setForeground:(UIColor *)color { self.duoGlyph.foreground=color; }

static double IDIDouble(id view, NSString *selector, double fallback) {
    SEL sel=NSSelectorFromString(selector);
    if (![view respondsToSelector:sel]) return fallback;
    return ((double(*)(id,SEL))objc_msgSend)(view,sel);
}
-(void)refreshFromBattery:(UIView *)battery wifi:(UIView *)wifi cell:(UIView *)cell {
    double level=IDIDouble(battery,@"chargePercent",80);
    if (level>1) level/=100.0;
    self.duoGlyph.charge=MAX(0,MIN(1,level));
    self.duoGlyph.charging=IDIDouble(battery,@"chargingState",0)!=0;
    self.duoGlyph.lowPower=IDIDouble(battery,@"saverModeActive",0)!=0;
    self.duoGlyph.showsPercent=IDIPrefBool("BatteryPercentageEnabled",YES);
    self.duoGlyph.wifiVisible=wifi!=nil;
    self.duoGlyph.wifiBars=wifi?(NSInteger)IDIDouble(wifi,@"numberOfActiveBars",3):0;
    self.duoGlyph.cellularBars=cell?(NSInteger)IDIDouble(cell,@"numberOfActiveBars",3):0;
    self.duoGlyph.contentScale=MAX(.3,MIN(1.5,IDIPrefDouble("RightNetworkIconScale",47)/100.0));
    [self.duoGlyph setNeedsDisplay];
}
@end
