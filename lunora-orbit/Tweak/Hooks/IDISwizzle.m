#import "IDICompat.h"
#import "IDIStatusBarSession.h"
#import "IDISwizzle.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

// One original IMP per class+selector pair. Sharing a single pointer across
// classes made the second install overwrite the first one's original, so the
// callback jumped into the wrong implementation and killed SpringBoard.
static IMP IDIOrigLayout;
static IMP IDIOrigWindow;
static IMP IDIHookedLayout;
static IMP IDIHookedWindow;

static void IDITickBar(id self) {
    @try {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        [[IDIStatusBarSession sessionForBar:self] attachToBar:self];
    } @catch (__unused NSException *e) {}
}

static void IDILayout(id self, SEL _cmd) {
    if (IDIOrigLayout) ((void (*)(id, SEL))IDIOrigLayout)(self, _cmd);
    IDITickBar(self);
}

static void IDIWindow(id self, SEL _cmd) {
    if (IDIOrigWindow) ((void (*)(id, SEL))IDIOrigWindow)(self, _cmd);
    IDITickBar(self);
}

static void IDIInstall(const char *name, SEL sel, IMP repl, IMP *orig) {
    Class cls = objc_getClass(name);
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP current = method_getImplementation(m);
    if (current == repl) return;
    MSHookMessageEx(cls, sel, repl, orig);
}

static void IDIInstallHooks(void) {
    if (!IDIHookedLayout) {
        IDIInstall("STUIStatusBar", @selector(layoutSubviews), (IMP)IDILayout, &IDIOrigLayout);
        IDIHookedLayout = (IMP)IDILayout;
    }
    if (!IDIHookedWindow) {
        IDIInstall("STUIStatusBar", @selector(didMoveToWindow), (IMP)IDIWindow, &IDIOrigWindow);
        IDIHookedWindow = (IMP)IDIWindow;
    }
}

void IDIInstallSwizzles(void) {
    IDIInstallHooks();
}
