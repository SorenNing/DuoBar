#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "PSCompat.h"
#import "IDICompat.h"
#import "PSCompat.h"

@interface IDISliderCell : PSSliderTableCell <UITextFieldDelegate> {
    UILabel *_idiTitleLabel;
    UITextField *_idiValueLabel;
    NSNumberFormatter *_idiNumberFormatter;
    NSString *_idiUnit;
    UISlider *_idiBoundSlider;
}
@property(nonatomic,strong) UILabel *idiTitleLabel;
@property(nonatomic,strong) UITextField *idiValueLabel;
@property(nonatomic,strong) NSNumberFormatter *idiNumberFormatter;
@property(nonatomic,copy) NSString *idiUnit;
@property(nonatomic,strong) UISlider *idiBoundSlider;
@end
