/*
 Copyright 2026 Adobe. All rights reserved.
 This file is licensed to you under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License. You may obtain a copy
 of the License at http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software distributed under
 the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
 OF ANY KIND, either express or implied. See the License for the specific language
 governing permissions and limitations under the License.
 */

#import "FlagDemoUIHelper.h"
#import "FlagDemoFetchConfig.h"

@implementation FlagDemoTheme

+ (UIColor *)backgroundColor {
    return [UIColor colorWithRed:0.96 green:0.97 blue:0.98 alpha:1.0];
}

+ (UIColor *)accentColor {
    return [UIColor colorWithRed:0.10 green:0.45 blue:0.91 alpha:1.0];
}

+ (UIColor *)onGreenColor {
    return [UIColor colorWithRed:0.30 green:0.69 blue:0.31 alpha:1.0];
}

+ (UIColor *)offGreyColor {
    return [UIColor colorWithRed:0.74 green:0.74 blue:0.74 alpha:1.0];
}

+ (UIColor *)errorOrangeColor {
    return [UIColor colorWithRed:1.0 green:0.60 blue:0.0 alpha:1.0];
}

+ (UIColor *)bodyTextColor {
    return [UIColor colorWithRed:0.22 green:0.28 blue:0.31 alpha:1.0];
}

@end

@implementation FlagDemoUIHelper

+ (UIView *)cardViewWithContent:(UIView *)content {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.whiteColor;
    card.layer.cornerRadius = 12.0;
    card.layer.shadowColor = UIColor.blackColor.CGColor;
    card.layer.shadowOpacity = 0.06;
    card.layer.shadowRadius = 2.0;
    card.layer.shadowOffset = CGSizeMake(0, 1);

    content.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [content.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [content.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [content.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16]
    ]];
    return card;
}

+ (UILabel *)titleLabelWithText:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.font = [UIFont boldSystemFontOfSize:16];
    label.textColor = UIColor.labelColor;
    label.numberOfLines = 0;
    return label;
}

+ (UILabel *)bodyLabelWithText:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.font = [UIFont systemFontOfSize:13];
    label.textColor = [FlagDemoTheme bodyTextColor];
    label.numberOfLines = 0;
    return label;
}

+ (UIButton *)primaryButtonWithTitle:(NSString *)title {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    button.backgroundColor = [FlagDemoTheme accentColor];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.layer.cornerRadius = 12.0;
    return button;
}

+ (UIActivityIndicatorView *)loadingIndicator {
    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    indicator.translatesAutoresizingMaskIntoConstraints = NO;
    indicator.color = UIColor.whiteColor;
    return indicator;
}

@end

@interface FlagDemoContextRowView : UIView
@property (nonatomic, strong) UITextField *keyField;
@property (nonatomic, strong) UITextField *valueField;
@property (nonatomic, copy) void (^onDelete)(void);
@end

@implementation FlagDemoContextRowView

- (instancetype)init {
    self = [super init];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.keyField = [[UITextField alloc] init];
        self.keyField.translatesAutoresizingMaskIntoConstraints = NO;
        self.keyField.placeholder = @"key";
        self.keyField.borderStyle = UITextBorderStyleRoundedRect;
        self.keyField.font = [UIFont systemFontOfSize:13];

        self.valueField = [[UITextField alloc] init];
        self.valueField.translatesAutoresizingMaskIntoConstraints = NO;
        self.valueField.placeholder = @"value";
        self.valueField.borderStyle = UITextBorderStyleRoundedRect;
        self.valueField.font = [UIFont systemFontOfSize:13];

        UIButton *deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
        deleteButton.translatesAutoresizingMaskIntoConstraints = NO;
        [deleteButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
        deleteButton.tintColor = [UIColor colorWithRed:0.90 green:0.22 blue:0.21 alpha:1.0];
        [deleteButton addTarget:self action:@selector(deleteTapped) forControlEvents:UIControlEventTouchUpInside];

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.keyField, self.valueField, deleteButton]];
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        stack.axis = UILayoutConstraintAxisHorizontal;
        stack.spacing = 8;
        stack.alignment = UIStackViewAlignmentCenter;
        [self addSubview:stack];

        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [self.keyField.widthAnchor constraintEqualToAnchor:self.valueField.widthAnchor],
            [deleteButton.widthAnchor constraintEqualToConstant:28]
        ]];
    }
    return self;
}

- (void)deleteTapped {
    if (self.onDelete) {
        self.onDelete();
    }
}

@end

@interface FlagDemoContextEditorView ()
@property (nonatomic, strong) UIStackView *rowsStack;
@property (nonatomic, strong) NSMutableArray<FlagDemoContextRowView *> *rowViews;
@property (nonatomic, strong) UILabel *ecidValueLabel;
@end

@implementation FlagDemoContextEditorView

- (instancetype)initWithEntries:(NSArray<FlagDemoContextEntry *> *)entries {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.rowViews = [NSMutableArray array];

        UIStackView *container = [[UIStackView alloc] init];
        container.translatesAutoresizingMaskIntoConstraints = NO;
        container.axis = UILayoutConstraintAxisVertical;
        container.spacing = 12;

        UIStackView *header = [[UIStackView alloc] init];
        header.axis = UILayoutConstraintAxisHorizontal;
        header.alignment = UIStackViewAlignmentCenter;

        UILabel *title = [FlagDemoUIHelper titleLabelWithText:@"Evaluation Context"];
        [title setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

        UIButton *addButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [addButton setImage:[UIImage systemImageNamed:@"plus.circle.fill"] forState:UIControlStateNormal];
        addButton.tintColor = [FlagDemoTheme accentColor];
        [addButton addTarget:self action:@selector(addRow) forControlEvents:UIControlEventTouchUpInside];

        [header addArrangedSubview:title];
        [header addArrangedSubview:addButton];
        [container addArrangedSubview:header];

        UIStackView *ecidRow = [[UIStackView alloc] init];
        ecidRow.axis = UILayoutConstraintAxisHorizontal;
        ecidRow.spacing = 8;
        UILabel *ecidLabel = [[UILabel alloc] init];
        ecidLabel.text = @"ECID";
        ecidLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        [ecidLabel.widthAnchor constraintEqualToConstant:72].active = YES;
        self.ecidValueLabel = [[UILabel alloc] init];
        NSString *ecid = [FlagDemoFetchConfig ecidValue];
        self.ecidValueLabel.text = ecid.length > 0 ? ecid : @"—";
        self.ecidValueLabel.font = [UIFont systemFontOfSize:12];
        self.ecidValueLabel.textColor = UIColor.secondaryLabelColor;
        self.ecidValueLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [ecidRow addArrangedSubview:ecidLabel];
        [ecidRow addArrangedSubview:self.ecidValueLabel];
        [container addArrangedSubview:ecidRow];

        self.rowsStack = [[UIStackView alloc] init];
        self.rowsStack.axis = UILayoutConstraintAxisVertical;
        self.rowsStack.spacing = 8;
        [container addArrangedSubview:self.rowsStack];

        [self addSubview:container];
        [NSLayoutConstraint activateConstraints:@[
            [container.topAnchor constraintEqualToAnchor:self.topAnchor],
            [container.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [container.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [container.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
        ]];

        self.entries = entries;
        [self reloadRows];
    }
    return self;
}

- (void)setEntries:(NSArray<FlagDemoContextEntry *> *)entries {
    _entries = [[entries mutableCopy] copy];
    [self reloadRows];
}

- (void)reloadRows {
    for (UIView *view in self.rowsStack.arrangedSubviews) {
        [self.rowsStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    [self.rowViews removeAllObjects];

    for (FlagDemoContextEntry *entry in self.entries) {
        [self appendRowWithEntry:entry];
    }
}

- (void)appendRowWithEntry:(FlagDemoContextEntry *)entry {
    FlagDemoContextRowView *row = [[FlagDemoContextRowView alloc] init];
    row.keyField.text = entry.key;
    row.valueField.text = entry.value;
    __weak typeof(self) weakSelf = self;
    __weak FlagDemoContextRowView *weakRow = row;
    row.onDelete = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        __strong FlagDemoContextRowView *strongRow = weakRow;
        if (strongSelf == nil || strongRow == nil) {
            return;
        }
        [strongSelf.rowsStack removeArrangedSubview:strongRow];
        [strongRow removeFromSuperview];
        [strongSelf.rowViews removeObject:strongRow];
    };
    [self.rowViews addObject:row];
    [self.rowsStack addArrangedSubview:row];
}

- (void)addRow {
    [self appendRowWithEntry:[FlagDemoContextEntry entryWithKey:@"" value:@""]];
}

- (NSArray<FlagDemoContextEntry *> *)currentEntries {
    NSMutableArray<FlagDemoContextEntry *> *entries = [NSMutableArray array];
    for (FlagDemoContextRowView *row in self.rowViews) {
        [entries addObject:[FlagDemoContextEntry entryWithKey:row.keyField.text ?: @""
                                                        value:row.valueField.text ?: @""]];
    }
    return entries;
}

- (void)updateEcid:(nullable NSString *)ecid {
    self.ecidValueLabel.text = ecid.length > 0 ? ecid : @"—";
}

@end
