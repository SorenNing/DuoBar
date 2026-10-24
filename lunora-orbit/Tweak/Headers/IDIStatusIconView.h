#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
@class DuoGlyphView, IDIStatusBarSession;

@interface IDIStatusIconView : UIView
@property(nonatomic,strong) IDIStatusBarSession *state;
@property(nonatomic,readonly,strong) DuoGlyphView *duoGlyph;
-(void)refreshFromBattery:(UIView *)battery wifi:(UIView *)wifi cell:(UIView *)cell;
-(void)setForeground:(UIColor *)color;
@end
