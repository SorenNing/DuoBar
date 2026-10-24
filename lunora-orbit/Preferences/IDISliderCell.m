#import "IDISliderCell.h"

@implementation IDISliderCell
-(instancetype)initWithStyle:(long)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    if ((self=[super initWithStyle:style reuseIdentifier:identifier specifier:specifier])) {
        self.selectionStyle=UITableViewCellSelectionStyleNone;
        self.accessoryType=UITableViewCellAccessoryNone;
        _idiTitleLabel=[UILabel new];
        _idiTitleLabel.font=[UIFont systemFontOfSize:16];
        _idiTitleLabel.textColor=UIColor.labelColor;
        _idiTitleLabel.adjustsFontSizeToFitWidth=YES;
        [self.contentView addSubview:_idiTitleLabel];
        _idiValueLabel=[UITextField new];
        _idiValueLabel.font=[UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightMedium];
        _idiValueLabel.textColor=UIColor.systemBlueColor;
        _idiValueLabel.textAlignment=NSTextAlignmentRight;
        _idiValueLabel.borderStyle=UITextBorderStyleNone;
        _idiValueLabel.keyboardType=UIKeyboardTypeDecimalPad;
        _idiValueLabel.delegate=self;
        [self.contentView addSubview:_idiValueLabel];
        self.idiNumberFormatter=[NSNumberFormatter new];
        self.idiNumberFormatter.numberStyle=NSNumberFormatterDecimalStyle;
        self.idiNumberFormatter.maximumFractionDigits=2;
        self.idiNumberFormatter.minimumFractionDigits=0;
        [self idiUpdateValue];
    }
    return self;
}
-(UISlider *)idiSlider {
    for (UIView *v in self.contentView.subviews) {
        if ([v isKindOfClass:UISlider.class]) return (UISlider *)v;
    }
    return nil;
}
-(void)idiUpdateValue {
    if (!self.specifier) return;
    _idiTitleLabel.text=[self.specifier propertyForKey:@"label"];
    _idiUnit=[self.specifier propertyForKey:@"DUIValueUnit"];
    id value=[self readPreferenceValue:self.specifier];
    double number=[value respondsToSelector:@selector(doubleValue)]?[value doubleValue]:0;
    self.idiValueLabel.text=[NSString stringWithFormat:@"%@%@",
        [self.idiNumberFormatter stringFromNumber:@(number)],_idiUnit ?: @""];
}
-(void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w=self.contentView.bounds.size.width;
    _idiTitleLabel.frame=CGRectMake(16,10,w-32,24);
    _idiValueLabel.frame=CGRectMake(w-130,10,114,24);
    UISlider *slider=self.idiSlider;
    if (slider) slider.frame=CGRectMake(16,38,w-32,32);
}
-(void)prepareForReuse {
    [super prepareForReuse];
    self.idiTitleLabel.text=nil;
    self.idiValueLabel.text=nil;
}
-(void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    [self idiUpdateValue];
}
-(void)controlChanged:(id)control { [self idiUpdateValue]; }
-(void)idiPreviewSlider:(id)control { [self idiUpdateValue]; }
-(void)idiWriteControl:(id)control { [self idiUpdateValue]; }
-(BOOL)idiCommitInput {
    NSNumber *number=[self.idiNumberFormatter numberFromString:self.idiValueLabel.text];
    if (!number) return NO;
    double min=[[self.specifier propertyForKey:@"min"] doubleValue];
    double max=[[self.specifier propertyForKey:@"max"] doubleValue];
    double n=MAX(min,MIN(max,number.doubleValue));
    [self setPreferenceValue:@(n) specifier:self.specifier];
    [self idiUpdateValue];
    return YES;
}
-(BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}
-(void)textFieldDidBeginEditing:(UITextField *)textField {
    NSString *text=self.idiValueLabel.text;
    if (_idiUnit.length && [text hasSuffix:_idiUnit])
        self.idiValueLabel.text=[text substringToIndex:text.length-_idiUnit.length];
}
-(void)textFieldDidEndEditing:(UITextField *)textField {
    if (![self idiCommitInput]) [self idiUpdateValue];
}
-(void)idiSubmitInput { [self.idiValueLabel resignFirstResponder]; }
-(void)idiCancelInput { [self idiUpdateValue]; [self.idiValueLabel resignFirstResponder]; }
@end
