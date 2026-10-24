#import "IDICircularGlassView.h"

@implementation IDICircularGlassView
-(instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO;
        self.isAccessibilityElement=NO;
        self.backgroundColor=UIColor.clearColor;
        self.opaque=NO;
        self.clipsToBounds=YES;
        self.layer.cornerRadius=MIN(CGRectGetWidth(frame),CGRectGetHeight(frame))/2;
    }
    return self;
}
-(void)updateWithDateBadge:(CGRect)badge fill:(UIColor *)fill opacity:(double)opacity foreground:(UIColor *)foreground {
    self.backgroundColor=[fill colorWithAlphaComponent:MAX(0,MIN(1,opacity))];
    self.layer.borderColor=foreground.CGColor;
    self.layer.borderWidth=0.7;
}
@end
