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

/// Defaults for Flags demo evaluation. Populate locally before running against a real environment.
@interface FlagDemoFetchConfig : NSObject

+ (NSString *)logTag;
+ (NSString *)launchAppId;
+ (NSString *)ecidNamespace;
+ (NSString *)ecidValue;
+ (NSDictionary<NSString *, NSArray<NSString *> *> *)baseAttributes;
+ (NSArray<NSString *> *)provisionFeatureKeys;
+ (NSString *)defaultFeatureKey;
+ (NSArray<FlagDemoContextEntry *> *)defaultContextEntries;

/// Example feature flags with friendly names, mirroring the Luma Flags reference app.
+ (NSArray<FlagDemoFeature *> *)knownFeatures;

/// Configuration keys published from Data Collection for the Flags extension.
/// Used by the runtime config-override panel (dev/testing only).
+ (NSString *)configKeyClientId;
+ (NSString *)configKeySandbox;
+ (NSString *)configKeyImsOrg;
+ (NSString *)configKeyEdgeDomain;

+ (NSDictionary<NSString *, NSArray<NSString *> *> *)mergedAttributesFromEntries:(NSArray<FlagDemoContextEntry *> *)entries;
+ (AEPFeatureEvaluationContext *)buildEvaluationContextFromEntries:(NSArray<FlagDemoContextEntry *> *)entries;

/// Builds a context, optionally injecting a custom identity (namespace + id) alongside the attributes.
+ (AEPFeatureEvaluationContext *)buildEvaluationContextFromEntries:(NSArray<FlagDemoContextEntry *> *)entries
                                                  customNamespace:(nullable NSString *)customNamespace
                                                         customId:(nullable NSString *)customId;

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
