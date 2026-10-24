#import <UIKit/UIKit.h>

// Duo-style status ring. The battery is the ring arc, the percentage sits in
// the top opening. The centre Wi-Fi fan and the bottom cellular bars are
// rendered from images taken of the real native status-bar glyphs, tinted with
// the bar's own foreground colour, so the ring shows the system icons rather
// than a look-alike redraw.
@interface DuoGlyphView : UIView

@property(nonatomic, assign) double charge;          // 0.0 .. 1.0
@property(nonatomic, assign) BOOL charging;
@property(nonatomic, assign) BOOL lowPower;
@property(nonatomic, assign) BOOL showsPercent;
@property(nonatomic, assign) BOOL wifiVisible;
@property(nonatomic, assign) NSInteger wifiBars;     // 0 .. 3 (fallback redraw)
@property(nonatomic, assign) NSInteger cellularBars; // 0 .. 4 (fallback redraw)
@property(nonatomic, assign) BOOL hotspotActive;
@property(nonatomic, assign) CGFloat contentScale;
@property(nonatomic, strong) UIColor *foreground;
@property(nonatomic, strong) UIImage *hotspotImage;

// Native glyph images (nil -> fall back to the drawn shape).
- (void)setNativeWifiImage:(UIImage *)image;
- (void)setNativeCellularImage:(UIImage *)image;

@end
