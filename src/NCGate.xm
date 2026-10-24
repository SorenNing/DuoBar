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


// NovaUnlock ships a self-made crash guard: its loader keeps a counter in
// /var/mobile/Library/Preferences/com.sanderzen.novaunlock.guard and, once that
// counter passes one, it refuses to load NovaUnlockCore.dylib at all. A respring
// inside the first eight seconds counts as a crash to it, so ordinary testing
// permanently switches the engine off. This gate clears the file and, if the
// engine still did not load, dlopens the core itself and starts it with no-op
// guard callbacks, so the counter can never disable the animations.
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <string.h>
#import <unistd.h>

#define DUO_GUARD_PATH "/var/mobile/Library/Preferences/com.sanderzen.novaunlock.guard"
#define DUO_CORE_PATH "/Library/MobileSubstrate/DynamicLibraries/NovaUnlockCore.dylib"
#define DUO_CORE_NAME "NovaUnlockCore.dylib"

static void DuoGuardNoop(void) {}

static BOOL DuoCoreLoaded(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, DUO_CORE_NAME)) return YES;
    }
    return NO;
}

static void DuoClearGuard(void) {
    unlink(DUO_GUARD_PATH);
}

static void DuoStartCoreDirectly(void) {
    if (DuoCoreLoaded()) return;
    DuoClearGuard();
    void *handle = dlopen(DUO_CORE_PATH, RTLD_NOW);
    if (!handle) return;
    void *entry = dlsym(handle, "u26_core_start");
    if (!entry) return;
    // The loader passes two callbacks: "mark running" and "schedule the health
    // reset". No-ops keep the guard permanently inert while the engine runs.
    ((void (*)(void *, void *))entry)((void *)DuoGuardNoop, (void *)DuoGuardNoop);
    NSLog(@"[DuoBar] NovaUnlock core started directly (guard bypassed)");
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
        DuoClearGuard();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                DuoInstallHooks();
                // The oscillator: clear the guard before and while the engine
                // loads, then start the core ourselves if it never arrived.
                for (int i = 0; i < 40; i++) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 50 * NSEC_PER_MSEC)),
                        dispatch_get_main_queue(), ^{ DuoClearGuard(); });
                }
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)),
                    dispatch_get_main_queue(), ^{ DuoStartCoreDirectly(); });
                [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(__unused NSTimer *timer) {
                    DuoTick();
                }];
            });
    }
}