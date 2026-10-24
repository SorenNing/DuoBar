#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
@class IDIStatusIconView;
@interface IDIRightSurface : UIView
@property(nonatomic,assign) BOOL controlCenter;
@property(nonatomic,strong) IDIStatusIconView *icon;
@property(nonatomic,weak) UIView *nativeBattery;
@property(nonatomic,readonly,strong) NSHashTable *nativeBatteries;
@property(nonatomic,strong) NSMapTable *nativeClipping;
@property(nonatomic,copy) id layoutHandler;
@property(nonatomic,assign) CGRect groupLayoutFrame;
@property(nonatomic,assign) CGRect groupContentFrame;
@property(nonatomic,assign) BOOL groupScrolling;
@property(nonatomic,strong) NSMapTable *groupMasks;
@property(nonatomic,strong) NSMapTable *groupOriginalMasks;
-(void)stopGroupMotion;
-(void)refreshGroupMotion;
-(void)freezeGroupScrolling;
-(void)clearGroupLayout;
-(double)groupPresentationOffset;
-(BOOL)groupAllowsHitAtPoint:(CGPoint)p;
-(void)registerNativeBattery:(id)battery;
-(void)updateGeometryInBar:(id)bar controlCenter:(BOOL)cc;
-(void)syncNativeMasks;
@end
