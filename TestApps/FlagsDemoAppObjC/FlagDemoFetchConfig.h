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

#import <Foundation/Foundation.h>

@class AEPFeatureEvaluationContext;
@class FlagDemoContextEntry;
@class FlagDemoFeature;

NS_ASSUME_NONNULL_BEGIN

/// Settings for the Flags demo. Set these locally before you run the demo against your own mobile property.
@interface FlagDemoFetchConfig : NSObject

+ (NSString *)logTag;

/// Environment File ID of your mobile property. In Data Collection, open your mobile property and
/// select Environments to find it. While this is empty, the demo shows a message and doesn't configure the SDK.
+ (NSString *)environmentFileId;

+ (NSDictionary<NSString *, NSArray<NSString *> *> *)baseAttributes;

/// Feature keys offered by the key picker on the Get Feature tab.
+ (NSArray<NSString *> *)featureKeys;

/// Initial feature key on the Get Feature tab. Empty when `knownFeatures` is empty.
+ (NSString *)defaultFeatureKey;
+ (NSArray<FlagDemoContextEntry *> *)defaultContextEntries;

/// Feature flags that the Flags tab evaluates. Empty by default: add the feature keys you created in
/// Experience Flags in FlagDemoFetchConfig.m. While this list is empty, the demo shows a message instead.
+ (NSArray<FlagDemoFeature *> *)knownFeatures;

/// Configuration keys published from Data Collection for the Flags extension.
/// Used by the runtime config-override panel (dev/testing only).
+ (NSString *)configKeyClientId;
+ (NSString *)configKeySandbox;
+ (NSString *)configKeyImsOrg;
+ (NSString *)configKeyEdgeDomain;

+ (NSDictionary<NSString *, NSArray<NSString *> *> *)mergedAttributesFromEntries:(NSArray<FlagDemoContextEntry *> *)entries;
+ (AEPFeatureEvaluationContext *)buildEvaluationContextFromEntries:(NSArray<FlagDemoContextEntry *> *)entries;

@end

/// Feature flag with a friendly display name and description.
@interface FlagDemoFeature : NSObject

@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *featureDescription;

+ (instancetype)featureWithKey:(NSString *)key displayName:(NSString *)displayName description:(NSString *)description;

@end

/// Editable evaluation-context key/value pair.
@interface FlagDemoContextEntry : NSObject

@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *value;

+ (instancetype)entryWithKey:(NSString *)key value:(NSString *)value;

@end

NS_ASSUME_NONNULL_END
