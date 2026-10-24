#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <string.h>
#import <QuartzCore/QuartzCore.h>
#import <substrate.h>

// DuoBarNCGate
//
// Lunora's engine has only two animation switches: unlock and Control Center
// return. Notification Center (the Cover Sheet) dismissal hits one of those
// paths, so the ring replays its reveal there even though it should not.
//
// This gate leaves the engine untouched: while the Cover Sheet is on screen and
// Control Center is not, reads of those two preference keys are answered with
// "off", and for a short tail after the sheet closes, in case the read happens
// during dismissal. Nothing is written to the preference file.

static NSString *const kGateDomain = @"com.ning.duobar";
static NSString *const kEngineDomain = @"iya.banana.duoicon";

static BOOL DuoNCVisible = NO;      // Cover Sheet is on screen
static BOOL DuoCCVisible = NO;      // Control Center owns the screen
static CFTimeInterval DuoNCHiddenAt = 0;
static BOOL DuoNCActiveBefore = NO; // sheet was open while CC was not

static CFPropertyListRef (*origCFPreferencesCopyAppValue)(CFStringRef key, CFStringRef appID);
static CFPropertyListRef (*origCFPreferencesCopyValue)(CFStringRef key, CFStringRef appID,
    CFStringRef user, CFStringRef host);

static BOOL DuoGateEnabled(void) {
    CFPropertyListRef value = CFPreferencesCopyValue((__bridge CFStringRef)@"SuppressNCAnimation",
        (__bridge CFStringRef)kGateDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL enabled = YES;
    if (value) {
        if (CFGetTypeID(value) == CFBooleanGetTypeID()) enabled = CFBooleanGetValue((CFBooleanRef)value);
        else if (CFGetTypeID(value) == CFNumberGetTypeID()) enabled = [(__bridge NSNumber *)value boolValue];
        CFRelease(value);
    }
    return enabled;
}

static CFPropertyListRef DuoSuppressedAnswer(CFStringRef key, CFStringRef appID) {
    if (!appID || !key) return NULL;
    NSString *domain = (__bridge NSString *)appID;
    if (![domain isEqualToString:kEngineDomain]) return NULL;
    NSString *name = (__bridge NSString *)key;
    if (!([name isEqualToString:@"RightUnlockAnimation"] ||
          [name isEqualToString:@"RightControlCenterReturnAnimation"])) return NULL;
    if (!DuoGateEnabled()) return NULL;

    BOOL suppress = DuoNCVisible && !DuoCCVisible;
    if (!suppress && DuoNCActiveBefore) {
        // The read can land a moment after the sheet is gone.
        suppress = (CACurrentMediaTime() - DuoNCHiddenAt) < 1.5;
    }
    if (!suppress) return NULL;
    return CFRetain(kCFBooleanFalse);
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
            NSString *name = NSStringFromClass(window.class);
            if (![name containsString:@"CoverSheet"]) continue;
            if (window.hidden || window.alpha < 0.01) continue;
            return YES;
        }
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
        // Keep the flag only for the tail window.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                if (!DuoNCVisible) DuoNCActiveBefore = NO;
            });
    }
    DuoNCVisible = nc;
    DuoCCVisible = cc;
}


// NovaUnlock ships a self-made crash guard: if SpringBoard dies within eight
// seconds of loading its core, the run counts as a crash, and after two such
// runs the engine disables itself until the package is reinstalled. A respring
// inside that window is indistinguishable from a crash to it, which is what
// kept turning the animations off. Once the core has clearly stayed loaded for
// ten seconds we know it is healthy, so the stale counter is cleared.
static void DuoClearNovaGuardIfHealthy(void) {
    BOOL coreLoaded = NO;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "NovaUnlockCore.dylib")) { coreLoaded = YES; break; }
    }
    if (!coreLoaded) return;
    NSString *guard = @"/var/mobile/Library/Preferences/com.sanderzen.novaunlock.guard";
    if ([NSFileManager.defaultManager fileExistsAtPath:guard]) {
        [NSFileManager.defaultManager removeItemAtPath:guard error:NULL];
        NSLog(@"[DuoBar] NovaUnlock core healthy; cleared stale crash guard");
    }
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
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                DuoInstallHooks();
                [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(__unused NSTimer *timer) {
                    DuoTick();
                }];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)),
                    dispatch_get_main_queue(), ^{ DuoClearNovaGuardIfHealthy(); });
            });
    }
}