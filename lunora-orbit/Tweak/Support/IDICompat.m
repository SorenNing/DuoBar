//  IDICompat.m
//  Preference plumbing. The binary reads every setting through CFPreferences
//  with the domain "iya.banana.iphoneduoicon" (CFPreferencesCopyAppValue and
//  CFPreferencesCopyMultiple are both in its import table), so the helpers
//  below mirror that access pattern exactly.
#import "IDICompat.h"
#import <CoreFoundation/CoreFoundation.h>

static CFStringRef IDIDomain(void) {
    static CFStringRef domain;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ domain = CFSTR("iya.banana.iphoneduoicon"); });
    return domain;
}

static CFStringRef IDIKey(const char *key) {
    return CFStringCreateWithCString(kCFAllocatorDefault, key, kCFStringEncodingUTF8);
}

id IDIPrefObject(const char *key) {
    if (!key) return nil;
    CFStringRef k = IDIKey(key);
    CFPropertyListRef v = CFPreferencesCopyAppValue(k, IDIDomain());
    CFRelease(k);
    return (__bridge_transfer id)v;
}

BOOL IDIPrefBool(const char *key, BOOL fallback) {
    id v = IDIPrefObject(key);
    if (!v) return fallback;
    if ([v respondsToSelector:@selector(boolValue)]) return [v boolValue];
    return fallback;
}

double IDIPrefDouble(const char *key, double fallback) {
    id v = IDIPrefObject(key);
    if (!v) return fallback;
    if ([v respondsToSelector:@selector(doubleValue)]) return [v doubleValue];
    return fallback;
}

long long IDIPrefInt(const char *key, long long fallback) {
    id v = IDIPrefObject(key);
    if (!v) return fallback;
    if ([v respondsToSelector:@selector(longLongValue)]) return [v longLongValue];
    return fallback;
}

void IDISetPrefBool(const char *key, BOOL value) {
    if (!key) return;
    CFStringRef k = IDIKey(key);
    CFPreferencesSetAppValue(k, (__bridge CFPropertyListRef)@(value), IDIDomain());
    CFRelease(k);
    CFPreferencesAppSynchronize(IDIDomain());
}

void IDIPostPreferencesChanged(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("iya.banana.iphoneduoicon/preferences-changed"),
                                         NULL, NULL, true);
}
