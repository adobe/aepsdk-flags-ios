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

#import "FlagDemoJSONHelper.h"
@import AEPFlags;

@implementation FlagDemoJSONHelper

+ (id)coerceVariantId:(NSString *)value {
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSInteger intValue = [trimmed integerValue];
    if ([trimmed isEqualToString:[NSString stringWithFormat:@"%ld", (long)intValue]]) {
        return @(intValue);
    }
    return value;
}

+ (NSString *)demoJSONStringForResult:(AEPFeatureEvaluationResult *)result {
    NSMutableDictionary *object = [NSMutableDictionary dictionary];
    object[@"id"] = @(result.id);
    object[@"key"] = result.key;

    if (result.featureGroupKey.length > 0) {
        object[@"featureGroupKey"] = result.featureGroupKey;
    }
    if (result.meta.length > 0) {
        object[@"meta"] = result.meta;
    }
    if (result.analyticsParam != nil) {
        NSMutableDictionary *analytics = [NSMutableDictionary dictionary];
        analytics[@"featureGroupId"] = @(result.analyticsParam.featureGroupId);
        analytics[@"featureId"] = @(result.analyticsParam.featureId);
        if (result.analyticsParam.variantId.length > 0) {
            analytics[@"variantId"] = [self coerceVariantId:result.analyticsParam.variantId];
        }
        object[@"analyticsParam"] = analytics;
    }

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:&error];
    if (data == nil || error != nil) {
        return @"{}";
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{}";
}

+ (NSString *)demoErrorStringForCode:(NSInteger)errorCode prefix:(NSString *)prefix {
    return [NSString stringWithFormat:@"%@(%ld)", prefix, (long)errorCode];
}

@end
