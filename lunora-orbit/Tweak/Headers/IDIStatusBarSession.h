#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
@class IDIRightSurface, IDIStatusIconView, IDIGlyphHandoff;
@interface IDIStatusBarSession : NSObject
@property(nonatomic,strong) IDIRightSurface *rightSurface;
@property(nonatomic,strong) IDIStatusIconView *controller;
@property(nonatomic,strong) IDIGlyphHandoff *handoff;
@property(nonatomic,copy) NSArray *rightReturnTrace;
@property(nonatomic,assign) BOOL pendingRightRevealRefresh;
@property(nonatomic,assign) BOOL pendingRightReturn;
@property(nonatomic,assign) BOOL rightSceneReturnRunning;
@property(nonatomic,strong) NSHashTable *leftTransitionTextLabels;
@property(nonatomic,strong) NSHashTable *leftTransitionCarrierLabels;
@property(nonatomic,assign) BOOL leftTransitionTextMaskActive;
+(instancetype)sessionForBar:(UIView *)bar;
-(void)attachToBar:(UIView *)bar;
-(void)recordRightReturnEvent:(id)event details:(id)details;
-(void)clearLeftTransitionTextMasks;
@end
