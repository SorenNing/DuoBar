//
//  PSCompat.h - Preferences framework shims for building the bundle
//
#ifndef PS_COMPAT_H
#define PS_COMPAT_H
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface PSSpecifier : NSObject
@property (nonatomic, retain) id target;
@property (nonatomic, retain) NSString *identifier;
@property (nonatomic, retain) NSMutableDictionary *properties;
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set
                                 get:(SEL)get detail:(Class)detail cell:(long)cell edit:(Class)edit;
- (id)propertyForKey:(NSString *)key;
- (void)setProperty:(id)value forKey:(NSString *)key;
@end

@interface PSListController : UIViewController
- (NSArray *)specifiers;
- (void)setSpecifiers:(NSArray *)specifiers;
- (id)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (id)specifierForID:(NSString *)identifier;
- (void)reloadSpecifiers;
- (void)reloadSpecifier:(id)specifier;
- (void)reloadSpecifierID:(NSString *)identifier;
- (id)readPreferenceValue:(id)specifier;
- (void)setPreferenceValue:(id)value specifier:(id)specifier;
@property (nonatomic, retain) UITableView *table;
@property (nonatomic, copy) NSString *title;
@end

@interface PSViewController : UIViewController
@end

@interface PSTableCell : UITableViewCell
- (instancetype)initWithStyle:(long)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(id)specifier;
@property (nonatomic, retain) id specifier;
@end

@interface PSSliderTableCell : PSTableCell
@end
#endif
