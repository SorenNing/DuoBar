#import "IDIRightSurface.h"
#import "IDIStatusIconView.h"

@implementation IDIRightSurface
-(instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        _nativeBatteries=[NSHashTable weakObjectsHashTable];
        _nativeClipping=[NSMapTable weakToStrongObjectsMapTable];
        self.backgroundColor=UIColor.clearColor;
        self.opaque=NO;
        self.clipsToBounds=YES;
    }
    return self;
}
-(void)stopGroupMotion {}
-(void)refreshGroupMotion {}
-(void)freezeGroupScrolling { self.groupScrolling=NO; }
-(void)clearGroupLayout { [self stopGroupMotion]; self.groupScrolling=NO; }
-(double)groupPresentationOffset { return self.groupContentFrame.origin.y-self.groupLayoutFrame.origin.y; }
-(BOOL)groupAllowsHitAtPoint:(CGPoint)p { return self.groupScrolling && CGRectContainsPoint(self.groupLayoutFrame,p); }
-(void)registerNativeBattery:(id)battery {
    if (!battery) return;
    [self.nativeBatteries addObject:battery];
    self.nativeBattery=battery;
}
-(void)updateGeometryInBar:(id)bar controlCenter:(BOOL)cc {
    self.controlCenter=cc;
    [self setNeedsLayout];
}
-(void)syncNativeMasks {}
-(void)layoutSubviews {
    [super layoutSubviews];
    self.icon.frame=self.bounds;
    if (self.layoutHandler) ((void (^)(void))self.layoutHandler)();
}
-(id)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    id hit=[super hitTest:p withEvent:e];
    return hit==self?nil:hit;
}
-(void)dealloc { [self stopGroupMotion]; }
@end
