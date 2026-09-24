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

#import "FlagDemoFetchConfig.h"
@import AEPFlags;

@implementation FlagDemoContextEntry

+ (instancetype)entryWithKey:(NSString *)key value:(NSString *)value {
    FlagDemoContextEntry *entry = [[FlagDemoContextEntry alloc] init];
    entry.key = key;
    entry.value = value;
    return entry;
}

@end

@implementation FlagDemoFeature

+ (instancetype)featureWithKey:(NSString *)key displayName:(NSString *)displayName description:(NSString *)description {
    FlagDemoFeature *feature = [[FlagDemoFeature alloc] init];
    feature.key = key;
    feature.displayName = displayName;
    feature.featureDescription = description;
    return feature;
}

@end

@implementation FlagDemoFetchConfig

+ (NSString *)logTag {
    return @"";
}

+ (NSString *)launchAppId {
    return @"";
}

+ (NSString *)ecidNamespace {
    return @"";
}

+ (NSString *)ecidValue {
    return @"";
}

+ (NSDictionary<NSString *, NSArray<NSString *> *> *)baseAttributes {
    return @{
        @"appVersion": @[@"6.0.0"],
        @"locale": @[@"en_US"],
        @"platform": @[@"iOS"]
    };
}

+ (NSArray<FlagDemoFeature *> *)knownFeatures {
    return @[
        [FlagDemoFeature featureWithKey:@"ai-assistant" displayName:@"AI Assistant" description:@"Example flag: AI assistant entry point"],
        [FlagDemoFeature featureWithKey:@"premium-support" displayName:@"Premium Support" description:@"Example flag: premium support card"],
        [FlagDemoFeature featureWithKey:@"loyalty-rewards" displayName:@"Loyalty Rewards" description:@"Example flag: loyalty & rewards"],
        [FlagDemoFeature featureWithKey:@"store-locator" displayName:@"Store Locator" description:@"Example flag: store locator tab"],
        [FlagDemoFeature featureWithKey:@"featured-products" displayName:@"Featured Products" description:@"Example flag: featured carousel"],
        [FlagDemoFeature featureWithKey:@"personalization-hub" displayName:@"Personalization Hub" description:@"Example flag: personalization/offers"],
        [FlagDemoFeature featureWithKey:@"push-promotions" displayName:@"Push Promotions" description:@"Example flag: promo notifications"],
        [FlagDemoFeature featureWithKey:@"member-login-badge" displayName:@"Member Login Badge" description:@"Example flag: member login badge"]
    ];
}

+ (NSArray<NSString *> *)provisionFeatureKeys {
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (FlagDemoFeature *feature in [self knownFeatures]) {
        [keys addObject:feature.key];
    }
    return keys;
}

+ (NSString *)defaultFeatureKey {
    return @"ai-assistant";
}

+ (NSString *)configKeyClientId { return @"flags.clientId"; }
+ (NSString *)configKeySandbox { return @"flags.sandbox"; }
+ (NSString *)configKeyImsOrg { return @"experienceCloud.org"; }
+ (NSString *)configKeyEdgeDomain { return @"edge.domain"; }

+ (NSArray<FlagDemoContextEntry *> *)defaultContextEntries {
    NSMutableArray<FlagDemoContextEntry *> *entries = [NSMutableArray array];
    NSArray<NSString *> *sortedKeys = [[self baseAttributes].allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in sortedKeys) {
        NSArray<NSString *> *values = [self baseAttributes][key];
        [entries addObject:[FlagDemoContextEntry entryWithKey:key value:values.firstObject ?: @""]];
    }
    return entries;
}

+ (NSDictionary<NSString *, NSArray<NSString *> *> *)mergedAttributesFromEntries:(NSArray<FlagDemoContextEntry *> *)entries {
    NSMutableDictionary<NSString *, NSArray<NSString *> *> *merged = [NSMutableDictionary dictionary];
    for (FlagDemoContextEntry *entry in entries) {
        if (entry.key.length == 0) {
            continue;
        }
        merged[entry.key] = @[entry.value ?: @""];
    }
    return merged;
}

+ (AEPFeatureEvaluationContext *)buildEvaluationContextFromEntries:(NSArray<FlagDemoContextEntry *> *)entries {
    return [[[AEPFeatureEvaluationContext builder]
        withAttributes:[self mergedAttributesFromEntries:entries]]
        build];
}

+ (AEPFeatureEvaluationContext *)buildEvaluationContextFromEntries:(NSArray<FlagDemoContextEntry *> *)entries
                                                  customNamespace:(nullable NSString *)customNamespace
                                                         customId:(nullable NSString *)customId {
    NSMutableDictionary<NSString *, NSArray<NSString *> *> *attributes = [[self mergedAttributesFromEntries:entries] mutableCopy];
    if (customNamespace.length > 0 && customId.length > 0) {
        attributes[customNamespace] = @[customId];
    }
    return [[[AEPFeatureEvaluationContext builder]
        withAttributes:attributes]
        build];
}

@end
