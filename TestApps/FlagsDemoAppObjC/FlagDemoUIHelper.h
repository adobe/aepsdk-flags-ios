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

#import <UIKit/UIKit.h>

@class FlagDemoContextEntry;

NS_ASSUME_NONNULL_BEGIN

@interface FlagDemoTheme : NSObject

+ (UIColor *)backgroundColor;
+ (UIColor *)accentColor;
+ (UIColor *)onGreenColor;
+ (UIColor *)offGreyColor;
+ (UIColor *)errorOrangeColor;
+ (UIColor *)bodyTextColor;

@end

@interface FlagDemoUIHelper : NSObject

+ (UIView *)cardViewWithContent:(UIView *)content;
+ (UILabel *)titleLabelWithText:(NSString *)text;
+ (UILabel *)bodyLabelWithText:(NSString *)text;
+ (UIButton *)primaryButtonWithTitle:(NSString *)title;
+ (UIActivityIndicatorView *)loadingIndicator;

@end

/// Reusable evaluation-context editor used by both demo tabs.
@interface FlagDemoContextEditorView : UIView

@property (nonatomic, copy) NSArray<FlagDemoContextEntry *> *entries;

- (instancetype)initWithEntries:(NSArray<FlagDemoContextEntry *> *)entries;
- (NSArray<FlagDemoContextEntry *> *)currentEntries;

/// Updates the ECID value shown in the editor header.
- (void)updateEcid:(nullable NSString *)ecid;

@end

NS_ASSUME_NONNULL_END
