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

#import "FlagsTestViewController.h"
#import "FlagDemoFetchConfig.h"
#import "FlagDemoJSONHelper.h"
#import "FlagDemoUIHelper.h"
@import AEPFlags;
@import AEPCore;
@import AEPEdgeIdentity;

@interface FlagDemoFeatureState : NSObject
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, copy, nullable) NSString *evaluationError;
@end

@implementation FlagDemoFeatureState
@end

@interface FlagsTestViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) FlagDemoContextEditorView *contextEditor;
@property (nonatomic, strong) UIButton *fetchButton;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) UIStackView *resultsStack;
@property (nonatomic, strong) UILabel *resultsTitleLabel;
@property (nonatomic, assign) NSInteger fetchCount;
@property (nonatomic, assign) BOOL isLoading;

// Identities
@property (nonatomic, copy, nullable) NSString *ecid;
@property (nonatomic, strong) UILabel *ecidValueLabel;

// Custom identity, set with Identity for Edge Network (never through the evaluation context)
@property (nonatomic, strong) UITextField *identityNamespaceField;
@property (nonatomic, strong) UITextField *identityIdField;

// Lifecycle
@property (nonatomic, strong) UISegmentedControl *lifecycleControl;

// Config override
@property (nonatomic, strong) UITextField *clientIdField;
@property (nonatomic, strong) UITextField *sandboxField;
@property (nonatomic, strong) UITextField *imsOrgField;
@property (nonatomic, strong) UITextField *edgeDomainField;

// Activity log
@property (nonatomic, strong) NSMutableArray<NSString *> *logLines;
@property (nonatomic, strong) UILabel *logLabel;
@end

@implementation FlagsTestViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [FlagDemoTheme backgroundColor];
    self.title = @"Flags";
    self.fetchCount = 0;
    self.logLines = [NSMutableArray array];
    [self buildUI];
    [self addLog:@"Flags SDK version: %@", [AEPMobileFlag extensionVersion]];
    [self refreshEcid];
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

    [self.contentStack addArrangedSubview:[self buildHeader]];
    [self.contentStack addArrangedSubview:[FlagDemoUIHelper cardViewWithContent:[FlagDemoUIHelper configStatusContent]]];
    [self.contentStack addArrangedSubview:[FlagDemoUIHelper cardViewWithContent:[self buildIdentitiesContent]]];
    if ([FlagDemoFetchConfig knownFeatures].count == 0) {
        [self.contentStack addArrangedSubview:[FlagDemoUIHelper cardViewWithContent:[FlagDemoUIHelper noFeatureKeysContent]]];
    }

    self.fetchButton = [FlagDemoUIHelper primaryButtonWithTitle:@"⟳  Fetch Features"];
    [self.fetchButton.heightAnchor constraintEqualToConstant:50].active = YES;
    [self.fetchButton addTarget:self action:@selector(fetchTapped) forControlEvents:UIControlEventTouchUpInside];
    self.loadingIndicator = [FlagDemoUIHelper loadingIndicator];
    [self.fetchButton addSubview:self.loadingIndicator];
    [NSLayoutConstraint activateConstraints:@[
        [self.loadingIndicator.centerXAnchor constraintEqualToAnchor:self.fetchButton.centerXAnchor],
        [self.loadingIndicator.centerYAnchor constraintEqualToAnchor:self.fetchButton.centerYAnchor]
    ]];
    [self.contentStack addArrangedSubview:self.fetchButton];

    self.resultsTitleLabel = [FlagDemoUIHelper titleLabelWithText:@""];
    self.resultsTitleLabel.hidden = YES;
    [self.contentStack addArrangedSubview:self.resultsTitleLabel];

    self.resultsStack = [[UIStackView alloc] init];
    self.resultsStack.axis = UILayoutConstraintAxisVertical;
    self.resultsStack.spacing = 0;
    [self.contentStack addArrangedSubview:self.resultsStack];

    self.contextEditor = [[FlagDemoContextEditorView alloc] initWithEntries:[FlagDemoFetchConfig defaultContextEntries]];
    [self.contentStack addArrangedSubview:[FlagDemoUIHelper cardViewWithContent:self.contextEditor]];

    [self.contentStack addArrangedSubview:[FlagDemoUIHelper cardViewWithContent:[self buildCustomIdentityContent]]];
    [self.contentStack addArrangedSubview:[FlagDemoUIHelper cardViewWithContent:[self buildLifecycleContent]]];
    [self.contentStack addArrangedSubview:[FlagDemoUIHelper cardViewWithContent:[self buildConfigOverrideContent]]];
    [self.contentStack addArrangedSubview:[FlagDemoUIHelper cardViewWithContent:[self buildActivityLogContent]]];
    [self.contentStack addArrangedSubview:[FlagDemoUIHelper cardViewWithContent:[self buildHelpContent]]];

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

#pragma mark - Section builders

- (UIView *)buildHeader {
    UIView *header = [[UIView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.backgroundColor = UIColor.whiteColor;
    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"Flags";
    title.font = [UIFont boldSystemFontOfSize:22];
    title.textColor = [FlagDemoTheme accentColor];
    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.text = [NSString stringWithFormat:@"Flags extension  |  v%@", [AEPMobileFlag extensionVersion]];
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
    return header;
}

- (UIView *)buildIdentitiesContent {
    UIStackView *content = [[UIStackView alloc] init];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 8;

    UIStackView *headerRow = [[UIStackView alloc] init];
    headerRow.axis = UILayoutConstraintAxisHorizontal;
    headerRow.alignment = UIStackViewAlignmentCenter;
    UILabel *title = [FlagDemoUIHelper titleLabelWithText:@"Identities"];
    [title setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    UIButton *refresh = [UIButton buttonWithType:UIButtonTypeSystem];
    [refresh setImage:[UIImage systemImageNamed:@"arrow.clockwise.circle.fill"] forState:UIControlStateNormal];
    refresh.tintColor = [FlagDemoTheme accentColor];
    [refresh addTarget:self action:@selector(refreshEcid) forControlEvents:UIControlEventTouchUpInside];
    [headerRow addArrangedSubview:title];
    [headerRow addArrangedSubview:refresh];
    [content addArrangedSubview:headerRow];

    UIStackView *ecidRow = [[UIStackView alloc] init];
    ecidRow.axis = UILayoutConstraintAxisHorizontal;
    ecidRow.spacing = 8;
    ecidRow.alignment = UIStackViewAlignmentCenter;

    UIStackView *valueStack = [[UIStackView alloc] init];
    valueStack.axis = UILayoutConstraintAxisVertical;
    valueStack.spacing = 2;
    UILabel *ecidCaption = [[UILabel alloc] init];
    ecidCaption.text = @"ECID";
    ecidCaption.font = [UIFont boldSystemFontOfSize:10];
    ecidCaption.textColor = UIColor.grayColor;
    self.ecidValueLabel = [[UILabel alloc] init];
    self.ecidValueLabel.text = @"Not available";
    self.ecidValueLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.ecidValueLabel.textColor = [FlagDemoTheme bodyTextColor];
    self.ecidValueLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [valueStack addArrangedSubview:ecidCaption];
    [valueStack addArrangedSubview:self.ecidValueLabel];
    [valueStack setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    UIButton *copy = [UIButton buttonWithType:UIButtonTypeSystem];
    [copy setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal];
    copy.tintColor = [FlagDemoTheme accentColor];
    [copy addTarget:self action:@selector(copyEcid) forControlEvents:UIControlEventTouchUpInside];

    [ecidRow addArrangedSubview:valueStack];
    [ecidRow addArrangedSubview:copy];
    [content addArrangedSubview:ecidRow];
    return content;
}

- (UIView *)buildCustomIdentityContent {
    UIStackView *content = [[UIStackView alloc] init];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 8;

    [content addArrangedSubview:[FlagDemoUIHelper titleLabelWithText:@"Custom Identity"]];

    UILabel *hint = [FlagDemoUIHelper bodyLabelWithText:
        @"Sets an identity with Identity for Edge Network. Flags that assign users by this namespace use it. The namespace must match the flag's namespace exactly, including case."];
    hint.font = [UIFont systemFontOfSize:12];
    hint.textColor = UIColor.grayColor;
    [content addArrangedSubview:hint];

    self.identityNamespaceField = [self makeLabeledField:@"Namespace" placeholder:@"for example, CRMID" intoStack:content];
    self.identityIdField = [self makeLabeledField:@"Identifier" placeholder:@"identity value" intoStack:content];

    UIButton *setIdentity = [FlagDemoUIHelper primaryButtonWithTitle:@"Set Identity"];
    [setIdentity.heightAnchor constraintEqualToConstant:44].active = YES;
    [setIdentity addTarget:self action:@selector(setCustomIdentityTapped) forControlEvents:UIControlEventTouchUpInside];
    [content addArrangedSubview:setIdentity];

    UIButton *removeIdentity = [FlagDemoUIHelper primaryButtonWithTitle:@"Remove Identity"];
    [removeIdentity.heightAnchor constraintEqualToConstant:44].active = YES;
    [removeIdentity addTarget:self action:@selector(removeCustomIdentityTapped) forControlEvents:UIControlEventTouchUpInside];
    [content addArrangedSubview:removeIdentity];
    return content;
}

- (nullable AEPIdentityItem *)customIdentityItem {
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *namespace = [self.identityNamespaceField.text stringByTrimmingCharactersInSet:whitespace];
    NSString *identifier = [self.identityIdField.text stringByTrimmingCharactersInSet:whitespace];
    if (namespace.length == 0 || identifier.length == 0) {
        return nil;
    }
    return [[AEPIdentityItem alloc] initWithId:identifier authenticatedState:AEPAuthenticatedStateAuthenticated primary:NO];
}

- (NSString *)trimmedIdentityNamespace {
    return [self.identityNamespaceField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)setCustomIdentityTapped {
    AEPIdentityItem *item = [self customIdentityItem];
    if (item == nil) {
        [self addLog:@"Custom identity not set: enter a namespace and an identifier"];
        return;
    }
    AEPIdentityMap *identityMap = [[AEPIdentityMap alloc] init];
    [identityMap addItem:item withNamespace:[self trimmedIdentityNamespace]];
    [AEPMobileEdgeIdentity updateIdentities:identityMap];
    [self addLog:@"Custom identity set in namespace %@", [self trimmedIdentityNamespace]];
}

- (void)removeCustomIdentityTapped {
    AEPIdentityItem *item = [self customIdentityItem];
    if (item == nil) {
        [self addLog:@"Custom identity not removed: enter a namespace and an identifier"];
        return;
    }
    [AEPMobileEdgeIdentity removeIdentityItem:item withNamespace:[self trimmedIdentityNamespace]];
    [self addLog:@"Custom identity removed from namespace %@", [self trimmedIdentityNamespace]];
}

- (UIView *)buildLifecycleContent {
    UIStackView *content = [[UIStackView alloc] init];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 8;
    [content addArrangedSubview:[FlagDemoUIHelper titleLabelWithText:@"App Lifecycle"]];
    UILabel *hint = [FlagDemoUIHelper bodyLabelWithText:@"Drives MobileCore lifecycleStart / lifecyclePause."];
    hint.font = [UIFont systemFontOfSize:12];
    hint.textColor = UIColor.grayColor;
    [content addArrangedSubview:hint];

    self.lifecycleControl = [[UISegmentedControl alloc] initWithItems:@[@"Foreground", @"Background"]];
    self.lifecycleControl.selectedSegmentIndex = 0;
    [self.lifecycleControl addTarget:self action:@selector(lifecycleChanged) forControlEvents:UIControlEventValueChanged];
    [content addArrangedSubview:self.lifecycleControl];
    return content;
}

- (UIView *)buildConfigOverrideContent {
    UIStackView *content = [[UIStackView alloc] init];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 8;
    [content addArrangedSubview:[FlagDemoUIHelper titleLabelWithText:@"Config Override"]];
    UILabel *hint = [FlagDemoUIHelper bodyLabelWithText:
        @"Runtime only — production apps use the Data Collection mobile property. Leave blank to skip a field."];
    hint.font = [UIFont systemFontOfSize:12];
    hint.textColor = UIColor.grayColor;
    [content addArrangedSubview:hint];

    self.clientIdField = [self makeLabeledField:@"Application ID" placeholder:@"flags.clientId" intoStack:content];
    self.sandboxField = [self makeLabeledField:@"Sandbox" placeholder:@"flags.sandbox" intoStack:content];
    self.imsOrgField = [self makeLabeledField:@"Org ID" placeholder:@"experienceCloud.org" intoStack:content];
    self.edgeDomainField = [self makeLabeledField:@"Edge Domain" placeholder:@"edge.domain" intoStack:content];

    UIButton *apply = [FlagDemoUIHelper primaryButtonWithTitle:@"Apply Config"];
    [apply.heightAnchor constraintEqualToConstant:44].active = YES;
    [apply addTarget:self action:@selector(applyConfigTapped) forControlEvents:UIControlEventTouchUpInside];
    [content addArrangedSubview:apply];
    return content;
}

- (UIView *)buildActivityLogContent {
    UIStackView *content = [[UIStackView alloc] init];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 8;

    UIStackView *headerRow = [[UIStackView alloc] init];
    headerRow.axis = UILayoutConstraintAxisHorizontal;
    headerRow.alignment = UIStackViewAlignmentCenter;
    UILabel *title = [FlagDemoUIHelper titleLabelWithText:@"Activity Log"];
    [title setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    UIButton *clear = [UIButton buttonWithType:UIButtonTypeSystem];
    [clear setTitle:@"Clear" forState:UIControlStateNormal];
    clear.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [clear setTitleColor:[UIColor colorWithRed:0.90 green:0.22 blue:0.21 alpha:1.0] forState:UIControlStateNormal];
    [clear addTarget:self action:@selector(clearLogTapped) forControlEvents:UIControlEventTouchUpInside];
    [headerRow addArrangedSubview:title];
    [headerRow addArrangedSubview:clear];
    [content addArrangedSubview:headerRow];

    self.logLabel = [[UILabel alloc] init];
    self.logLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.logLabel.textColor = [FlagDemoTheme bodyTextColor];
    self.logLabel.numberOfLines = 0;
    self.logLabel.text = @"No activity yet.";
    [content addArrangedSubview:self.logLabel];
    return content;
}

- (UIView *)buildHelpContent {
    UIStackView *helpContent = [[UIStackView alloc] init];
    helpContent.axis = UILayoutConstraintAxisVertical;
    helpContent.spacing = 8;
    [helpContent addArrangedSubview:[FlagDemoUIHelper titleLabelWithText:@"Interpreting flag results"]];
    [helpContent addArrangedSubview:[FlagDemoUIHelper bodyLabelWithText:
        @"Green = Flag.isFeatureEnabled returned true for this ECID + Evaluation Context. Grey = returned false (the feature doesn't exist, the targeting rules don't match, or the user is in a control group)."]];
    [helpContent addArrangedSubview:[FlagDemoUIHelper bodyLabelWithText:@"Orange dot + Error line = the error callback ran, for example because of a timeout or missing configuration. Check the console logs."]];
    UILabel *note = [FlagDemoUIHelper bodyLabelWithText:@"Fetch Features evaluates the keys one at a time."];
    note.font = [UIFont systemFontOfSize:12];
    note.textColor = UIColor.grayColor;
    [helpContent addArrangedSubview:note];
    return helpContent;
}

/// Builds a "Label [textfield]" horizontal row and appends it to the given stack.
- (UITextField *)makeLabeledField:(NSString *)label placeholder:(NSString *)placeholder intoStack:(UIStackView *)stack {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 8;
    row.alignment = UIStackViewAlignmentCenter;
    UILabel *caption = [[UILabel alloc] init];
    caption.text = label;
    caption.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [caption.widthAnchor constraintEqualToConstant:96].active = YES;
    UITextField *field = [[UITextField alloc] init];
    field.placeholder = placeholder;
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.font = [UIFont systemFontOfSize:13];
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [row addArrangedSubview:caption];
    [row addArrangedSubview:field];
    [stack addArrangedSubview:row];
    return field;
}

#pragma mark - Identity / lifecycle / config actions

- (void)refreshEcid {
    __weak typeof(self) weakSelf = self;
    [AEPMobileEdgeIdentity getExperienceCloudId:^(NSString * _Nullable ecid, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            if (ecid.length > 0) {
                strongSelf.ecid = ecid;
                strongSelf.ecidValueLabel.text = ecid;
                [strongSelf.contextEditor updateEcid:ecid];
                NSString *prefix = ecid.length > 8 ? [ecid substringToIndex:8] : ecid;
                [strongSelf addLog:@"ECID: %@…", prefix];
            } else if (error != nil) {
                [strongSelf addLog:@"ECID resolution failed: %@", error.localizedDescription];
            } else {
                [strongSelf addLog:@"ECID not available yet"];
            }
        });
    }];
}

- (void)copyEcid {
    if (self.ecid.length > 0) {
        UIPasteboard.generalPasteboard.string = self.ecid;
    }
}

- (void)lifecycleChanged {
    if (self.lifecycleControl.selectedSegmentIndex == 0) {
        [AEPMobileCore lifecycleStart:nil];
        [self addLog:@"FOREGROUND — lifecycleStart, flag refresh resumes"];
    } else {
        [AEPMobileCore lifecyclePause];
        [self addLog:@"BACKGROUND — lifecyclePause, flag refresh paused, pending exposures sent"];
    }
}

- (void)applyConfigTapped {
    NSMutableDictionary<NSString *, id> *update = [NSMutableDictionary dictionary];
    if (self.clientIdField.text.length > 0) { update[[FlagDemoFetchConfig configKeyClientId]] = self.clientIdField.text; }
    if (self.sandboxField.text.length > 0) { update[[FlagDemoFetchConfig configKeySandbox]] = self.sandboxField.text; }
    if (self.imsOrgField.text.length > 0) { update[[FlagDemoFetchConfig configKeyImsOrg]] = self.imsOrgField.text; }
    if (self.edgeDomainField.text.length > 0) { update[[FlagDemoFetchConfig configKeyEdgeDomain]] = self.edgeDomainField.text; }

    if (update.count == 0) {
        [self addLog:@"Config override skipped: all fields empty"];
        return;
    }
    [AEPMobileCore updateConfiguration:update];
    NSArray<NSString *> *keys = [update.allKeys sortedArrayUsingSelector:@selector(compare:)];
    [self addLog:@"Config override applied: %@", [keys componentsJoinedByString:@", "]];
}

#pragma mark - Activity log

- (void)addLog:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm:ss.SSS";
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    NSString *line = [NSString stringWithFormat:@"%@  %@", [formatter stringFromDate:[NSDate date]], message];
    // On-screen activity log only — intentionally does not write to the console
    // so the SDK's backend/network logs stay readable there.

    [self.logLines insertObject:line atIndex:0];
    while (self.logLines.count > 100) {
        [self.logLines removeLastObject];
    }
    self.logLabel.text = self.logLines.count > 0 ? [self.logLines componentsJoinedByString:@"\n"] : @"No activity yet.";
}

- (void)clearLogTapped {
    [self.logLines removeAllObjects];
    self.logLabel.text = @"No activity yet.";
}

#pragma mark - Fetch

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

- (void)fetchTapped {
    if (self.isLoading) {
        return;
    }
    NSArray<FlagDemoFeature *> *features = [FlagDemoFetchConfig knownFeatures];
    if (features.count == 0) {
        [self addLog:@"No feature keys to evaluate. Add keys to knownFeatures in FlagDemoFetchConfig.m."];
        return;
    }
    self.isLoading = YES;
    [self addLog:@"Fetching %lu features via isFeatureEnabled()", (unsigned long)features.count];

    AEPFeatureEvaluationContext *context = [FlagDemoFetchConfig buildEvaluationContextFromEntries:self.contextEditor.currentEntries];
    NSMutableArray<FlagDemoFeatureState *> *results = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    __block void (^evaluateNext)(NSInteger);
    evaluateNext = ^(NSInteger index) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        if (index >= (NSInteger)features.count) {
            [strongSelf finishBatchWithResults:results];
            return;
        }
        FlagDemoFeature *feature = features[(NSUInteger)index];
        [AEPMobileFlag isFeatureEnabled:feature.key
                      evaluationContext:context
                             completion:^(BOOL enabled) {
            dispatch_async(dispatch_get_main_queue(), ^{
                FlagDemoFeatureState *state = [[FlagDemoFeatureState alloc] init];
                state.key = feature.key;
                state.displayName = feature.displayName;
                state.enabled = enabled;
                [results addObject:state];
                [strongSelf addLog:@"%@ -> %@", feature.key, enabled ? @"ON" : @"OFF"];
                evaluateNext(index + 1);
            });
        } errorCallback:^(enum AEPError error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *message = [FlagDemoJSONHelper demoErrorStringForCode:error prefix:@"fetch_error"];
                FlagDemoFeatureState *state = [[FlagDemoFeatureState alloc] init];
                state.key = feature.key;
                state.displayName = feature.displayName;
                state.enabled = NO;
                state.evaluationError = message;
                [results addObject:state];
                [strongSelf addLog:@"Error: %@ — %@", feature.key, message];
                evaluateNext(index + 1);
            });
        }];
    };
    evaluateNext(0);
}

- (void)finishBatchWithResults:(NSMutableArray<FlagDemoFeatureState *> *)results {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.fetchCount += 1;
        self.subtitleLabel.text = [NSString stringWithFormat:@"Flags extension  |  v%@  |  Fetch #%ld",
                                   [AEPMobileFlag extensionVersion], (long)self.fetchCount];
        self.isLoading = NO;

        [results sortUsingComparator:^NSComparisonResult(FlagDemoFeatureState *left, FlagDemoFeatureState *right) {
            return [left.key compare:right.key];
        }];

        NSInteger enabledCount = 0;
        NSInteger errorCount = 0;
        for (FlagDemoFeatureState *state in results) {
            if (state.evaluationError != nil) {
                errorCount += 1;
            } else if (state.enabled) {
                enabledCount += 1;
            }
        }
        [self addLog:@"Fetch complete: %ld/%lu on, %ld errors",
              (long)enabledCount, (unsigned long)results.count, (long)errorCount];

        self.resultsTitleLabel.hidden = results.count == 0;
        self.resultsTitleLabel.text = [NSString stringWithFormat:@"Feature Flags (%ld/%lu on, %ld errors)",
                                       (long)enabledCount, (unsigned long)results.count, (long)errorCount];

        for (UIView *view in self.resultsStack.arrangedSubviews) {
            [self.resultsStack removeArrangedSubview:view];
            [view removeFromSuperview];
        }

        if (results.count == 0) {
            return;
        }

        UIStackView *cardContent = [[UIStackView alloc] init];
        cardContent.axis = UILayoutConstraintAxisVertical;
        cardContent.spacing = 0;
        for (NSUInteger index = 0; index < results.count; index++) {
            FlagDemoFeatureState *state = results[index];
            [cardContent addArrangedSubview:[self rowViewForState:state]];
            if (index + 1 < results.count) {
                UIView *divider = [[UIView alloc] init];
                divider.translatesAutoresizingMaskIntoConstraints = NO;
                divider.backgroundColor = [UIColor colorWithRed:0.94 green:0.94 blue:0.94 alpha:1.0];
                [divider.heightAnchor constraintEqualToConstant:1].active = YES;
                [cardContent addArrangedSubview:divider];
            }
        }
        [self.resultsStack addArrangedSubview:[FlagDemoUIHelper cardViewWithContent:cardContent]];
    });
}

- (UIView *)rowViewForState:(FlagDemoFeatureState *)state {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.layoutMargins = UIEdgeInsetsMake(10, 12, 10, 12);
    row.layoutMarginsRelativeArrangement = YES;

    UIStackView *textStack = [[UIStackView alloc] init];
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.spacing = 3;
    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.text = state.displayName.length > 0 ? state.displayName : state.key;
    nameLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    nameLabel.textColor = [FlagDemoTheme bodyTextColor];
    [textStack addArrangedSubview:nameLabel];
    UILabel *keyLabel = [[UILabel alloc] init];
    keyLabel.text = state.key;
    keyLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    keyLabel.textColor = UIColor.grayColor;
    [textStack addArrangedSubview:keyLabel];
    if (state.evaluationError.length > 0) {
        UILabel *errorLabel = [[UILabel alloc] init];
        errorLabel.text = [NSString stringWithFormat:@"Error: %@", state.evaluationError];
        errorLabel.font = [UIFont systemFontOfSize:11];
        errorLabel.textColor = [UIColor colorWithRed:0.90 green:0.32 blue:0.0 alpha:1.0];
        errorLabel.numberOfLines = 0;
        [textStack addArrangedSubview:errorLabel];
    }
    [textStack setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    UILabel *chip = [[UILabel alloc] init];
    chip.font = [UIFont boldSystemFontOfSize:11];
    chip.textAlignment = NSTextAlignmentCenter;
    UIColor *chipColor;
    if (state.evaluationError.length > 0) {
        chip.text = @"  ERR  ";
        chipColor = [FlagDemoTheme errorOrangeColor];
    } else if (state.enabled) {
        chip.text = @"  ON  ";
        chipColor = [FlagDemoTheme onGreenColor];
    } else {
        chip.text = @"  OFF  ";
        chipColor = [FlagDemoTheme offGreyColor];
    }
    chip.textColor = chipColor;
    chip.backgroundColor = [chipColor colorWithAlphaComponent:0.12];
    chip.layer.cornerRadius = 11;
    chip.layer.masksToBounds = YES;
    chip.layer.borderWidth = 1;
    chip.layer.borderColor = [chipColor colorWithAlphaComponent:0.35].CGColor;
    [chip.heightAnchor constraintEqualToConstant:22].active = YES;

    [row addArrangedSubview:textStack];
    [row addArrangedSubview:chip];
    return row;
}

@end
