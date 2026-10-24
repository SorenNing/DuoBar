#ifndef IDI_COMPAT_H
#define IDI_COMPAT_H
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

#ifndef IDI_PACKAGE_ID
#define IDI_PACKAGE_ID "iya.banana.iphoneduoicon"
#endif

@class IDIRightSurface, IDIStatusIconView, IDIStatusBarSession;
@class DuoGlyphView;

@protocol IDINativeLayerOwner <NSObject>
@end
@protocol STUIStatusBarDisplayable <NSObject>
@end

@interface STUIStatusBar : UIView
@end
@interface STUIStatusBarForegroundView : UIView
@end
@interface STUIStatusBarImageView : UIImageView
@end
@interface STUIStatusBarStringView : UILabel
@end
@interface STUIStatusBarBatteryView : UIView
@end
@interface _UIBatteryView : UIView
@end
@interface _UIStatusBarWifiSignalView : UIView
@end
@interface _UIStatusBarCellularSignalView : UIView
@end
@interface STUIStatusBarWifiSignalView : UIView
@end
@interface STUIStatusBarCellularSignalView : UIView
@end

extern id IDIPrefObject(const char *key);
extern BOOL IDIPrefBool(const char *key, BOOL fallback);
extern double IDIPrefDouble(const char *key, double fallback);
extern long long IDIPrefInt(const char *key, long long fallback);
extern void IDISetPrefBool(const char *key, BOOL value);
extern void IDIPostPreferencesChanged(void);
#endif
