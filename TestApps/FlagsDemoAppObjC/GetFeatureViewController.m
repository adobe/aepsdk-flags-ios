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

#import "GetFeatureViewController.h"
#import "FlagDemoFetchConfig.h"
#import "FlagDemoJSONHelper.h"
#import "FlagDemoUIHelper.h"
@import AEPFlags;
@import AEPEdgeIdentity;

@interface GetFeatureViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UITextField *featureKeyField;
@property (nonatomic, strong) FlagDemoContextEditorView *contextEditor;
@property (nonatomic, strong) UIButton *fetchButton;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) UIStackView *resultContainer;
@property (nonatomic, assign) NSInteger fetchCount;
@property (nonatomic, assign) BOOL isLoading;
@end

@implementation GetFeatureViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [FlagDemoTheme backgroundColor];
    self.title = @"Get Feature";
    self.fetchCount = 0;
    [self buildUI];
    [self refreshEcid];
}

- (void)refreshEcid {
    __weak typeof(self) weakSelf = self;
    [AEPMobileEdgeIdentity getExperienceCloudId:^(NSString * _Nullable ecid, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf != nil && ecid.length > 0) {
                [strongSelf.contextEditor updateEcid:ecid];
            }
        });
    }];
}

- (void)buildUI {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];

    self.contentStack = [[UIStackView alloc] init];
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentStack.axis = UILayoutConstraintAxisVertical;
    self.contentStack.spacing = 16;
    [self.scrollView addSubview:self.contentStack];

    UIView *header = [[UIView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.backgroundColor = UIColor.whiteColor;
    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"Get Feature";
    title.font = [UIFont boldSystemFontOfSize:22];
    title.textColor = [FlagDemoTheme accentColor];
    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.text = @"Flag.getFeature API";
    self.subtitleLabel.font = [UIFont systemFontOfSize:12];
    self.subtitleLabel.textColor = UIColor.grayColor;
    [header addSubview:title];
    [header addSubview:self.subtitleLabel];
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:header.topAnchor constant:16],
        [title.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [title.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [self.subtitleLabel.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4],
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [self.subtitleLabel.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-16]
    ]];
    [self.contentStack addArrangedSubview:header];

    UIStackView *statusContent = [[UIStackView alloc] init];
    statusContent.axis = UILayoutConstraintAxisHorizontal;
    statusContent.spacing = 8;
    statusContent.alignment = UIStackViewAlignmentCenter;
    UIView *statusDot = [[UIView alloc] init];
    statusDot.translatesAutoresizingMaskIntoConstraints = NO;
    statusDot.backgroundColor = [FlagDemoTheme onGreenColor];
    statusDot.layer.cornerRadius = 5;
    [statusDot.widthAnchor constraintEqualToConstant:10].active = YES;
    [statusDot.heightAnchor constraintEqualToConstant:10].active = YES;
    UILabel *statusLabel = [[UILabel alloc] init];
    statusLabel.text = @"Flags: ready";
    statusLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [statusContent addArrangedSubview:statusDot];
    [statusContent addArrangedSubview:statusLabel];
    [self.contentStack addArrangedSubview:[FlagDemoUIHelper cardViewWithContent:statusContent]];

    UIStackView *featureKeyContent = [[UIStackView alloc] init];
    featureKeyContent.axis = UILayoutConstraintAxisVertical;
    featureKeyContent.spacing = 8;
    [featureKeyContent addArrangedSubview:[FlagDemoUIHelper titleLabelWithText:@"Feature Key"]];
    self.featureKeyField = [[UITextField alloc] init];
    self.featureKeyField.translatesAutoresizingMaskIntoConstraints = NO;
    self.featureKeyField.placeholder = @"feature key";
    self.featureKeyField.borderStyle = UITextBorderStyleRoundedRect;
    self.featureKeyField.font = [UIFont systemFontOfSize:13];
    self.featureKeyField.text = [FlagDemoFetchConfig defaultFeatureKey];
    [featureKeyContent addArrangedSubview:self.featureKeyField];
    UIButton *pickerButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [pickerButton setTitle:@"Choose provisioned key" forState:UIControlStateNormal];
    pickerButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    pickerButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    [pickerButton addTarget:self action:@selector(showFeatureKeyPicker) forControlEvents:UIControlEventTouchUpInside];
    [featureKeyContent addArrangedSubview:pickerButton];
    [self.contentStack addArrangedSubview:[FlagDemoUIHelper cardViewWithContent:featureKeyContent]];

    self.contextEditor = [[FlagDemoContextEditorView alloc] initWithEntries:[FlagDemoFetchConfig defaultContextEntries]];
    [self.contentStack addArrangedSubview:[FlagDemoUIHelper cardViewWithContent:self.contextEditor]];

    UIStackView *helpContent = [[UIStackView alloc] init];
    helpContent.axis = UILayoutConstraintAxisVertical;
    helpContent.spacing = 8;
    [helpContent addArrangedSubview:[FlagDemoUIHelper titleLabelWithText:@"Interpreting getFeature results"]];
    [helpContent addArrangedSubview:[FlagDemoUIHelper bodyLabelWithText:
        @"Returns JSON for the FeatureEvaluationResult when a match exists, or null when no match is found."]];
    [helpContent addArrangedSubview:        [FlagDemoUIHelper bodyLabelWithText:@"Orange Error card = SDK callback failed (network, IMS, or server error). Check console logs."]];
    [self.contentStack addArrangedSubview:[FlagDemoUIHelper cardViewWithContent:helpContent]];

    self.fetchButton = [FlagDemoUIHelper primaryButtonWithTitle:@"Get Feature"];
    [self.fetchButton.heightAnchor constraintEqualToConstant:50].active = YES;
    [self.fetchButton addTarget:self action:@selector(fetchTapped) forControlEvents:UIControlEventTouchUpInside];
    self.loadingIndicator = [FlagDemoUIHelper loadingIndicator];
    [self.fetchButton addSubview:self.loadingIndicator];
    [NSLayoutConstraint activateConstraints:@[
        [self.loadingIndicator.centerXAnchor constraintEqualToAnchor:self.fetchButton.centerXAnchor],
        [self.loadingIndicator.centerYAnchor constraintEqualToAnchor:self.fetchButton.centerYAnchor]
    ]];
    [self.contentStack addArrangedSubview:self.fetchButton];

    self.resultContainer = [[UIStackView alloc] init];
    self.resultContainer.axis = UILayoutConstraintAxisVertical;
    self.resultContainer.spacing = 8;
    [self.contentStack addArrangedSubview:self.resultContainer];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.contentStack.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:16],
        [self.contentStack.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor constant:16],
        [self.contentStack.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor constant:-16],
        [self.contentStack.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-24],
        [self.contentStack.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor constant:-32]
    ]];
}

- (void)setIsLoading:(BOOL)isLoading {
    _isLoading = isLoading;
    self.fetchButton.enabled = !isLoading;
    self.fetchButton.titleLabel.alpha = isLoading ? 0.0 : 1.0;
    if (isLoading) {
        [self.loadingIndicator startAnimating];
    } else {
        [self.loadingIndicator stopAnimating];
    }
}

- (void)showFeatureKeyPicker {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Provisioned keys"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *key in [FlagDemoFetchConfig provisionFeatureKeys]) {
        [alert addAction:[UIAlertAction actionWithTitle:key style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            self.featureKeyField.text = key;
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)fetchTapped {
    NSString *trimmedKey = [self.featureKeyField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmedKey.length == 0 || self.isLoading) {
        return;
    }

    self.isLoading = YES;
    [self clearResultViews];

    AEPFeatureEvaluationContext *context = [FlagDemoFetchConfig buildEvaluationContextFromEntries:self.contextEditor.currentEntries];
    __weak typeof(self) weakSelf = self;
    [AEPMobileFlag getFeature:trimmedKey
            evaluationContext:context
                   completion:^(AEPFeatureEvaluationResult * _Nullable result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            strongSelf.fetchCount += 1;
            strongSelf.subtitleLabel.text = [NSString stringWithFormat:@"Flag.getFeature API  |  Fetch #%ld", (long)strongSelf.fetchCount];
            strongSelf.isLoading = NO;
            if (result != nil) {
                NSString *json = [FlagDemoJSONHelper demoJSONStringForResult:result];
                [strongSelf showResultCardWithTitle:@"JSON Response" body:json isError:NO];
            } else {
                [strongSelf showResultCardWithTitle:@"JSON Response" body:@"null" isError:NO];
            }
        });
    } errorCallback:^(enum AEPError error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            strongSelf.fetchCount += 1;
            strongSelf.subtitleLabel.text = [NSString stringWithFormat:@"Flag.getFeature API  |  Fetch #%ld", (long)strongSelf.fetchCount];
            strongSelf.isLoading = NO;
            NSString *message = [FlagDemoJSONHelper demoErrorStringForCode:error prefix:@"getFeature_error"];
            [strongSelf showResultCardWithTitle:@"Error" body:message isError:YES];
        });
    }];
}

- (void)clearResultViews {
    for (UIView *view in self.resultContainer.arrangedSubviews) {
        [self.resultContainer removeArrangedSubview:view];
        [view removeFromSuperview];
    }
}

- (void)showResultCardWithTitle:(NSString *)title body:(NSString *)body isError:(BOOL)isError {
    [self clearResultViews];

    UIStackView *section = [[UIStackView alloc] init];
    section.axis = UILayoutConstraintAxisVertical;
    section.spacing = 8;

    UIStackView *header = [[UIStackView alloc] init];
    header.axis = UILayoutConstraintAxisHorizontal;
    header.spacing = 8;
    header.alignment = UIStackViewAlignmentCenter;
    if (isError) {
        UIView *dot = [[UIView alloc] init];
        dot.translatesAutoresizingMaskIntoConstraints = NO;
        dot.backgroundColor = [FlagDemoTheme errorOrangeColor];
        dot.layer.cornerRadius = 5;
        [dot.widthAnchor constraintEqualToConstant:10].active = YES;
        [dot.heightAnchor constraintEqualToConstant:10].active = YES;
        [header addArrangedSubview:dot];
    }
    [header addArrangedSubview:[FlagDemoUIHelper titleLabelWithText:title]];
    [section addArrangedSubview:header];

    UILabel *bodyLabel = [[UILabel alloc] init];
    bodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    bodyLabel.text = body;
    bodyLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    bodyLabel.textColor = isError ? [UIColor colorWithRed:0.90 green:0.32 blue:0.0 alpha:1.0] : [FlagDemoTheme bodyTextColor];
    bodyLabel.numberOfLines = 0;
    [section addArrangedSubview:[FlagDemoUIHelper cardViewWithContent:bodyLabel]];
    [self.resultContainer addArrangedSubview:section];
}

@end
