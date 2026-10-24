#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "IDICompat.h"

@interface IDIRightPreferences : NSObject
{
    BOOL _dock;
    BOOL _recent;
    BOOL _showOrbit;
    BOOL _roundIcons;
    BOOL _favoritesOnlyNotifications;
    BOOL _notificationFavoritesPreview;
    unsigned long long _count;
    double _orbitScale;
    double _orbitXOffset;
    double _iconScale;
    NSDictionary *_folders;
    NSArray *_applications;
    NSDictionary *_applicationNames;
}
@property (nonatomic, readonly, assign) BOOL dock;
@property (nonatomic, readonly, assign) BOOL recent;
@property (nonatomic, readonly, assign) BOOL showOrbit;
@property (nonatomic, readonly, assign) BOOL roundIcons;
@property (nonatomic, readonly, assign) BOOL favoritesOnlyNotifications;
@property (nonatomic, readonly, assign) BOOL notificationFavoritesPreview;
@property (nonatomic, readonly, assign) unsigned long long count;
@property (nonatomic, readonly, assign) double orbitScale;
@property (nonatomic, readonly, assign) double orbitXOffset;
@property (nonatomic, readonly, assign) double iconScale;
@property (nonatomic, copy, readonly) NSDictionary *folders;
@property (nonatomic, copy, readonly) NSArray *applications;
@property (nonatomic, copy, readonly) NSDictionary *applicationNames;

-(BOOL) isEqualToRightPreferences:(id)arg1;
-(BOOL)dock;
-(BOOL)recent;
-(BOOL)showOrbit;
-(BOOL)roundIcons;
-(BOOL)favoritesOnlyNotifications;
-(BOOL)notificationFavoritesPreview;
-(unsigned long long)count;
-(double)orbitScale;
-(double)orbitXOffset;
-(double)iconScale;
-(id)folders;
-(id)applications;
-(id)applicationNames;
@end
