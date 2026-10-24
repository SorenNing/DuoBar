#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

// DuoBarGate
//
// Two independent jobs, both done by intercepting the engine's preference reads
// instead of patching the engine binary:
//
// 1. Notification Center: the engine only knows "unlock" and "Control Center
//    return", so dismissing the Cover Sheet replays the reveal. While the sheet
//    is up those two keys read as false.
//
// 2. Native-first unlock: the reveal begins from a snapshot, so real system
//    icons are replaced almost immediately. After an unlock the two keys read as
//    false for `NativeHold` seconds, letting the true native icons sit on screen
//    first; once that window passes the engine takes over normally.

static NSString *const kGateDomain = @"com.ning.duobar";
static NSString *const kEngineDomain = @"iya.banana.duoicon";

static BOOL DuoNCVisible = NO;
static BOOL DuoCCVisible = NO;
static CFTimeInterval DuoNCHiddenAt = 0;
static BOOL DuoNCActiveBefore = NO;

static BOOL DuoHolding = NO;
static CFTimeInterval DuoHoldUntil = 0;

static CFPropertyListRef (*origCFPreferencesCopyAppValue)(CFStringRef, CFStringRef);
static CFPropertyListRef (*origCFPreferencesCopyValue)(CFStringRef, CFStringRef, CFStringRef, CFStringRef);

static CFPropertyListRef DuoCopy(NSString *key, NSString *domain) {
    CFStringRef k = (__bridge CFStringRef)key;
    CFStringRef d = (__bridge CFStringRef)domain;
    return CFPreferencesCopyValue(k, d, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

static double DuoDouble(NSString *key, double fallback) {
    CFPropertyListRef v = DuoCopy(key, kGateDomain);
    double out = fallback;
    if (v) {
        if (CFGetTypeID(v) == CFNumberGetTypeID()) out = [(__bridge NSNumber *)v doubleValue];
        else if (CFGetTypeID(v) == CFBooleanGetTypeID()) out = CFBooleanGetValue((CFBooleanRef)v) ? 1 : 0;
        CFRelease(v);
    }
    return out;
}

static BOOL DuoBool(NSString *key, BOOL fallback) {
    return DuoDouble(key, fallback ? 1 : 0) != 0;
}

static CFPropertyListRef DuoSuppressedAnswer(CFStringRef keyRef, CFStringRef appRef) {
    if (!keyRef || !appRef) return NULL;
    if (![(__bridge NSString *)appRef isEqualToString:kEngineDomain]) return NULL;
    NSString *key = (__bridge NSString *)keyRef;
    if (!([key isEqualToString:@"RightUnlockAnimation"] ||
          [key isEqualToString:@"RightControlCenterReturnAnimation"])) return NULL;

    // Notification Center window.
    BOOL suppress = NO;
    if (DuoBool(@"SuppressNCAnimation", YES) && DuoNCVisible && !DuoCCVisible) suppress = YES;
    if (!suppress && DuoNCActiveBefore && (CACurrentMediaTime() - DuoNCHiddenAt) < 1.5) suppress = YES;

    // Native-first hold window.
    if (!suppress && DuoHolding) {
        if (CACurrentMediaTime() < DuoHoldUntil) suppress = YES;
        else DuoHolding = NO;
    }

    return suppress ? CFRetain(kCFBooleanFalse) : NULL;
}

static CFPropertyListRef DuoCopyAppValue(CFStringRef key, CFStringRef appID) {
    CFPropertyListRef forced = DuoSuppressedAnswer(key, appID);
    if (forced) return forced;
    return origCFPreferencesCopyAppValue(key, appID);
}

static CFPropertyListRef DuoCopyValue(CFStringRef key, CFStringRef appID, CFStringRef user, CFStringRef host) {
    CFPropertyListRef forced = DuoSuppressedAnswer(key, appID);
    if (forced) return forced;
    return origCFPreferencesCopyValue(key, appID, user, host);
}

static BOOL DuoControlCenterVisible(void) {
    Class cls = NSClassFromString(@"SBControlCenterController");
    SEL shared = NSSelectorFromString(@"sharedInstance");
    if (!cls || ![cls respondsToSelector:shared]) return NO;
    id controller = ((id (*)(id, SEL))objc_msgSend)(cls, shared);
    for (NSString *name in @[@"isVisible", @"isPresented"]) {
        SEL selector = NSSelectorFromString(name);
        if ([controller respondsToSelector:selector] &&
            ((BOOL (*)(id, SEL))objc_msgSend)(controller, selector)) return YES;
    }
    return NO;
}

static BOOL DuoCoverSheetVisible(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (![[NSStringFromClass(window.class) lowercaseString] containsString:@"coversheet"]) continue;
            if (window.hidden || window.alpha < 0.01) continue;
            return YES;
        }
    }
    return NO;
}

static BOOL DuoDeviceLocked(void) {
    Class cls = NSClassFromString(@"SBLockScreenManager");
    SEL shared = NSSelectorFromString(@"sharedInstance");
    if (!cls || ![cls respondsToSelector:shared]) return NO;
    id manager = ((id (*)(id, SEL))objc_msgSend)(cls, shared);
    for (NSString *name in @[@"isLockScreenVisible", @"isUILocked"]) {
        SEL selector = NSSelectorFromString(name);
        if ([manager respondsToSelector:selector] &&
            ((BOOL (*)(id, SEL))objc_msgSend)(manager, selector)) return YES;
    }
    return NO;
}

static void DuoTick(void) {
    BOOL cc = DuoControlCenterVisible();
    BOOL nc = DuoCoverSheetVisible() && !cc;
    if (nc) {
        DuoNCActiveBefore = YES;
    } else if (DuoNCVisible) {
        DuoNCHiddenAt = CACurrentMediaTime();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                if (!DuoNCVisible) DuoNCActiveBefore = NO;
            });
    }
    DuoNCVisible = nc;
    DuoCCVisible = cc;

    // Unlock edge: start the native-first hold window.
    static BOOL wasLocked = YES;
    BOOL locked = DuoDeviceLocked();
    if (wasLocked && !locked) {
        double hold = DuoDouble(@"NativeHold", 0.4);
        if (hold > 0.001) {
            DuoHolding = YES;
            DuoHoldUntil = CACurrentMediaTime() + hold;
        }
    }
    wasLocked = locked;
}

static void DuoInstallHooks(void) {
    MSHookFunction((void *)CFPreferencesCopyAppValue, (void *)DuoCopyAppValue,
        (void **)&origCFPreferencesCopyAppValue);
    MSHookFunction((void *)CFPreferencesCopyValue, (void *)DuoCopyValue,
        (void **)&origCFPreferencesCopyValue);
}

__attribute__((constructor)) static void DuoGateInit(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                DuoInstallHooks();
                [NSTimer scheduledTimerWithTimeInterval:0.15 repeats:YES block:^(__unused NSTimer *timer) {
                    DuoTick();
                }];
            });
    }
}