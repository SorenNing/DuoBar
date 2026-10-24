#ifndef PS_COMPAT_H
#define PS_COMPAT_H
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, PSCellType) {
    PSGroupCell = 0,
    PSLinkCell,
    PSLinkListCell,
    PSListItemCell,
    PSTitleValueCell,
    PSSliderCell,
    PSSwitchCell,
    PSStaticTextCell,
    PSEditTextCell,
    PSSegmentCell,
    PSGiantIconCell,
    PSGiantCell,
    PSSecureEditTextCell,
    PSButtonCell,
    PSEditTextViewCell,
    PSSpinnerCell
};

@interface PSSpecifier : NSObject
@property(nonatomic,retain) id target;
@property(nonatomic,retain) NSString *identifier;
@property(nonatomic,retain) NSMutableDictionary *properties;
@property(nonatomic,assign) SEL buttonAction;
+(instancetype)groupSpecifierWithName:(NSString *)name;
+(instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set
    get:(SEL)get detail:(Class)detail cell:(long)cell edit:(Class)edit;
-(id)propertyForKey:(NSString *)key;
-(void)setProperty:(id)value forKey:(NSString *)key;
@end

@interface PSListController : UIViewController {
    NSMutableArray *_specifiers;
}
-(NSMutableArray *)specifiers;
-(void)setSpecifiers:(NSArray *)specifiers;
-(id)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
-(id)specifierForID:(NSString *)identifier;
-(void)reloadSpecifiers;
-(void)reloadSpecifier:(id)specifier;
-(void)reloadSpecifier:(id)specifier animated:(BOOL)animated;
-(void)reloadSpecifierID:(NSString *)identifier;
-(id)readPreferenceValue:(id)specifier;
-(void)setPreferenceValue:(id)value specifier:(id)specifier;
@property(nonatomic,retain) UITableView *table;
@property(nonatomic,copy) NSString *title;
@end

@interface PSViewController : UIViewController
@end

@interface PSTableCell : UITableViewCell
-(instancetype)initWithStyle:(long)style reuseIdentifier:(NSString *)identifier specifier:(id)specifier;
@property(nonatomic,retain) id specifier;
-(void)refreshCellContentsWithSpecifier:(id)specifier;
@end

@interface PSSliderTableCell : PSTableCell
-(id)readPreferenceValue:(id)specifier;
-(void)setPreferenceValue:(id)value specifier:(id)specifier;
@end
#endif
