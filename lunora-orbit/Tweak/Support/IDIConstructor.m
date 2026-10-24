#import "IDICompat.h"
#import "IDISwizzle.h"
#import "IDIStatusBarSession.h"

static void IDIScanTree(UIView *view) {
    if (!view) return;
    if ([NSStringFromClass(view.class) isEqualToString:@"STUIStatusBar"]) {
        [[IDIStatusBarSession sessionForBar:view] attachToBar:view];
        return;
    }
    for (UIView *sub in view.subviews) IDIScanTree(sub);
}

__attribute__((constructor)) static void IDILunoraBootstrap(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/mobile/Library/com.ning.duobar/disabled"]) return;
        IDIInstallSwizzles();
        for (double delay=0.5;delay<=6;delay+=0.75) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),
                dispatch_get_main_queue(),^{
                    IDIInstallSwizzles();
                    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                        if (![scene isKindOfClass:UIWindowScene.class]) continue;
                        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                            if (!window.hidden) for (UIView *view in window.subviews) IDIScanTree(view);
                        }
                    }
                });
        }
    }
}
