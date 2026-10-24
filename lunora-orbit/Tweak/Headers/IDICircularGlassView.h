#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
@interface IDICircularGlassView : UIView
@property(nonatomic,assign) BOOL standardCapsuleCorners;
@property(nonatomic,assign) BOOL fullEdgeHighlight;
@property(nonatomic,assign) BOOL suppressOuterHighlight;
@property(nonatomic,assign) BOOL outlineDefinesSurface;
@property(nonatomic,copy) UIBezierPath *outlineFillPath;
@property(nonatomic,assign) BOOL liquidAppearance;
@property(nonatomic,assign) double liquidMaterialOpacity;
-(void)updateWithDateBadge:(CGRect)badge fill:(UIColor *)fill opacity:(double)opacity foreground:(UIColor *)foreground;
@end
