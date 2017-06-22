//
//  ELODToolbox.h
//  EasyLoginOD
//
//  Created by Yoann Gini on 05/06/2017.
//  Copyright © 2017 Yoann Gini (Open Source Project). All rights reserved.
//

#import <Foundation/Foundation.h>
#include <odmodule/odcore.h>

@interface ELODToolbox : NSObject

+ (instancetype)sharedInstance;

- (NSDictionary*)standardInfoFromNativeInfo:(NSDictionary*)nativeInfo ofType:(NSString *)nativeType;

- (NSString*)nativeAttrbuteForNativeType:(NSString *)nativeType relatedToStandardAttribute:(NSString*)standardAttribute;

- (NSArray*)allNativeAttributeSupportedForType:(NSString *)nativeType;

- (BOOL)validatePassword:(NSString*)password againstAuthenticationMethods:(NSDictionary*)authMethods;

+ (NSString*)humanReadableODMatchType:(ODMatchType)matchType;
+ (NSString*)humanReadableODEqualityRule:(eODEqualityRule)equalityRule;
+ (NSDictionary*)humanReadableODPredicateDictionary:(NSDictionary *)inputDict;
+ (NSString*)singleLineDescriptionForObject:(id)object;

+ (NSDictionary*)nativePredicateEquivalence:(NSDictionary *)odPredicate;
+ (NSArray*)nativePredicatesEquivalence:(NSArray *)odPredicates;
@end
