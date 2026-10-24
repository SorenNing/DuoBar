#import "IDICompat.h"
#import "IDIStatusBarSession.h"
#import "IDISwizzle.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static IMP IDIOrigLayout;
static IMP IDIOrigWindow;
static IMP IDIOrigSuperview;

static void IDITickBar(id self) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    [[IDIStatusBarSession sessionForBar:self] attachToBar:self];
}
static void IDILayout(id self,SEL _cmd) {
    if (IDIOrigLayout) ((void(*)(id,SEL))IDIOrigLayout)(self,_cmd);
    IDITickBar(self);
}
static void IDIWindow(id self,SEL _cmd) {
    if (IDIOrigWindow) ((void(*)(id,SEL))IDIOrigWindow)(self,_cmd);
    IDITickBar(self);
}
static void IDISuperview(id self,SEL _cmd) {
    if (IDIOrigSuperview) ((void(*)(id,SEL))IDIOrigSuperview)(self,_cmd);
    IDITickBar(self);
}

static IMP IDIInstall(const char *name,SEL sel,IMP repl,IMP *orig) {
    Class cls=objc_getClass(name);
    if (!cls) return NULL;
    Method m=class_getInstanceMethod(cls,sel);
    if (!m) return NULL;
    IMP current=method_getImplementation(m);
    if (current==repl) return NULL;
    MSHookMessageEx(cls,sel,repl,orig);
    return current;
}

void IDIInstallSwizzles(void) {
    IDIInstall("STUIStatusBar",@selector(layoutSubviews),(IMP)IDILayout,&IDIOrigLayout);
    IDIInstall("STUIStatusBar",@selector(didMoveToWindow),(IMP)IDIWindow,&IDIOrigWindow);
    IDIInstall("STUIStatusBar",@selector(didMoveToSuperview),(IMP)IDISuperview,&IDIOrigSuperview);
    IDIInstall("STUIStatusBarImageView",@selector(didMoveToWindow),(IMP)IDIWindow,&IDIOrigWindow);
    IDIInstall("STUIStatusBarStringView",@selector(didMoveToWindow),(IMP)IDIWindow,&IDIOrigWindow);
}
