#import "IDIRootListController.h"

@implementation IDIRootListController
-(instancetype)init {
    if ((self=[super init])) self.title=@"DuoBar";
    return self;
}
-(void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"DuoBar";
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)self, NULL,
        CFSTR("iya.banana.duoicon/preferences-changed"), NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
}
-(void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)self, CFSTR("iya.banana.duoicon/preferences-changed"), NULL);
}
-(id)preferencesPlistName { return @"Root"; }
-(id)specifiers { return [self loadSpecifiersFromPlistName:@"Root" target:self]; }
-(id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key=[specifier propertyForKey:@"key"];
    NSString *domain=[specifier propertyForKey:@"defaults"] ?: @"iya.banana.duoicon";
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
    CFPropertyListRef value=CFPreferencesCopyAppValue((__bridge CFStringRef)key,
        (__bridge CFStringRef)domain);
    if (value) return (__bridge_transfer id)value;
    return [specifier propertyForKey:@"default"];
}
-(void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key=[specifier propertyForKey:@"key"];
    if (!key.length) return;
    NSString *domain=[specifier propertyForKey:@"defaults"] ?: @"iya.banana.duoicon";
    CFPreferencesSetAppValue((__bridge CFStringRef)key,(__bridge CFPropertyListRef)value,
        (__bridge CFStringRef)domain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("iya.banana.duoicon/preferences-changed"),NULL,NULL,true);
    [self reloadSpecifier:specifier];
}
@end
