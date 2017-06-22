//
//  ELODToolbox.m
//  EasyLoginOD
//
//  Created by Yoann Gini on 05/06/2017.
//  Copyright © 2017 Yoann Gini (Open Source Project). All rights reserved.
//

#import "ELODToolbox.h"

#include <odmodule/odcore.h>

#import "Common.h"

#import <CommonCrypto/CommonDigest.h>

@interface ELODToolbox ()

@property NSDictionary *mapping;

@end

@implementation ELODToolbox

+ (instancetype)sharedInstance {
    static id sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [self new];
    });
    return sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _mapping = [NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"ELMapping" ofType:@"plist"]];
    }
    return self;
}

// Will return the same content if nativeType isn't translated
- (NSDictionary*)standardInfoFromNativeInfo:(NSDictionary*)nativeInfo ofType:(NSString *)nativeType {
    // We recieve a native type and a bunch of native key/value or key/[values] that we need to translate to standard key/[value] record
    
    // We load the related translation table that can link a standard key to one native key
    NSDictionary *standardToNativeAttributesMap = [[self.mapping objectForKey:nativeType] objectForKey:kEasyLoginMappingInfosStandardToNativeKey];
    
    NSMutableDictionary *translatedInfo = [NSMutableDictionary new];
    
    [translatedInfo addEntriesFromDictionary:@{
                                               kODAttributeTypeUserShell: @[@"/bin/bash"],
                                               kODAttributeTypePrimaryGroupID: @[@"20"],
                                               }];
    
    [translatedInfo setObject:@[nativeType] forKey:kODAttributeTypeRecordType];
    
    // Then start the dance, first we look at native keys available in the current context
    for (NSString *nativeKeyToTranslate in [nativeInfo allKeys]) {
        
        // Then for each native key we found in the provided context, we look at standard who can be built with
        NSSet *relatedStandardKeys = [standardToNativeAttributesMap keysOfEntriesPassingTest:^BOOL(id  _Nonnull key, NSString *  _Nonnull obj, BOOL * _Nonnull stop) {
            return [obj isEqualToString:nativeKeyToTranslate];
        }];
        
        for (NSString *standardKey in relatedStandardKeys) {
            
            NSMutableArray *valuesForStandardKey = [NSMutableArray new];
            
            id availableNativeValues = [nativeInfo objectForKey:nativeKeyToTranslate];
            NSArray *nativeValuesAsObject;
            
            if ([availableNativeValues isKindOfClass:[NSArray class]]) {
                nativeValuesAsObject = availableNativeValues;
            } else {
                nativeValuesAsObject = @[availableNativeValues];
            }
            
            for (id nativeValue in nativeValuesAsObject) {
                [valuesForStandardKey addObject:[NSString stringWithFormat:@"%@", nativeValue]];
            }
            
            [translatedInfo setObject:valuesForStandardKey forKey:standardKey];
        }
    }
    
    [translatedInfo setObject:@[[[[NSUUID alloc] initWithUUIDString:@"96D036F8-8B22-4B97-9176-51FF063EF0E8"] UUIDString]]
                       forKey:kODAttributeTypeGUID];
    
    [translatedInfo setObject:@[[NSString stringWithFormat:@"/Users/%@", [[translatedInfo objectForKey:kODAttributeTypeRecordName] lastObject]]] forKey:kODAttributeTypeNFSHomeDirectory];
    
    return translatedInfo;
}

- (NSString*)nativeAttrbuteForNativeType:(NSString *)nativeType relatedToStandardAttribute:(NSString*)standardAttribute {
    return [[[self.mapping objectForKey:nativeType] objectForKey:kEasyLoginMappingInfosStandardToNativeKey] objectForKey:standardAttribute];
}

- (NSArray*)allNativeAttributeSupportedForType:(NSString *)nativeType {
    return [[[self.mapping objectForKey:nativeType] objectForKey:kEasyLoginMappingInfosStandardToNativeKey] allValues];
}

- (BOOL)validatePassword:(NSString*)password againstAuthenticationMethods:(NSDictionary*)authMethods {
    NSData *rawPassword = [password dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    
    CC_SHA256(rawPassword.bytes, (CC_LONG)rawPassword.length, digest);
    
    NSMutableString* sha256String = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    
    // Parse through the CC_SHA256 results (stored inside of digest[]).
    for(int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [sha256String appendFormat:@"%02x", digest[i]];
    }

    return [sha256String isEqualToString:[authMethods objectForKey:@"sha256"]];
}


+ (NSString*) humanReadableODMatchType:(ODMatchType)matchType
{
    if((matchType & 0x0100) > 0) return [NSString stringWithFormat:@"DEPRECATED MATCH TYPE (CASE INSENSITIVE NOW DEFINED IN ATTR SCHEMA!) : %@",[self humanReadableODMatchType:(0xF0FF & matchType)]];
    
    switch (matchType) {
        case kODMatchAny:
            return @"kODMatchAny";
            break;
            
        case kODMatchEqualTo:
            return @"kODMatchEqualTo";
            break;
        case kODMatchBeginsWith:
            return @"kODMatchBeginsWith";
            break;
        case kODMatchEndsWith:
            return @"kODMatchEndsWith";
            break;
        case kODMatchContains:
            return @"kODMatchContains";
            break;
            
        case kODMatchGreaterThan:
            return @"kODMatchGreaterThan";
            break;
        case kODMatchLessThan:
            return @"kODMatchLessThan";
            break;
            
        default:
            return [NSString stringWithFormat:@"UNKNOWN kODMatch value:%ld",(long)matchType];
            break;
    }
}

+ (NSString*) humanReadableODEqualityRule:(eODEqualityRule)equalityRule
{
    switch (equalityRule) {
        case eODEqualityRuleNone:
            return @"eODEqualityRuleNone";
            break;
        case eODEqualityRuleCaseIgnore:
            return @"eODEqualityRuleCaseIgnore";
            break;
        case eODEqualityRuleCaseExact:
            return @"eODEqualityRuleCaseExact";
            break;
        case eODEqualityRuleNumber:
            return @"eODEqualityRuleNumber";
            break;
        case eODEqualityRuleCertificate:
            return @"eODEqualityRuleCertificate";
            break;
        case eODEqualityRuleTime:
            return @"eODEqualityRuleTime";
            break;
        case eODEqualityRuleTelephoneNumber:
            return @"eODEqualityRuleTelephoneNumber";
            break;
        case eODEqualityRuleOctetMatch:
            return @"eODEqualityRuleOctetMatch";
            break;
            
        default:
            return [NSString stringWithFormat:@"UNKNOWN eODEqualityRule value:%ld",(long)equalityRule];
            break;
    }
    
}

+ (NSDictionary*) humanReadableODPredicateDictionary:(NSDictionary *)inputDict
{
    NSMutableDictionary *outputDict = [inputDict mutableCopy];
    if(inputDict[[NSString stringWithUTF8String:kODKeyPredicateMatchType]] != nil) {
        outputDict[[NSString stringWithUTF8String:kODKeyPredicateMatchType]] = [self humanReadableODMatchType:[inputDict[[NSString stringWithUTF8String:kODKeyPredicateMatchType]] unsignedIntValue]];
    }
    
    if(inputDict[[NSString stringWithUTF8String:kODKeyPredicateEquality]] != nil) {
        outputDict[[NSString stringWithUTF8String:kODKeyPredicateEquality]] = [self humanReadableODEqualityRule:[inputDict[[NSString stringWithUTF8String:kODKeyPredicateEquality]] unsignedIntValue]];
    }
    
    return outputDict;
}

+ (NSString*)singleLineDescriptionForObject:(id)object
{
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}




+ (NSString*)nativeMatchTypeEquivalence:(ODMatchType)matchType
{
    if((matchType & 0x0100) > 0) return [self nativeMatchTypeEquivalence:(0xF0FF & matchType)];
    
    switch (matchType) {
        case kODMatchAny:
            return @"any";
            break;
            
        case kODMatchEqualTo:
            return @"equalTo";
            break;
        case kODMatchBeginsWith:
            return @"beginsWith";
            break;
        case kODMatchEndsWith:
            return @"endsWith";
            break;
        case kODMatchContains:
            return @"contains";
            break;
            
        case kODMatchGreaterThan:
            return @"greaterThan";
            break;
        case kODMatchLessThan:
            return @"lessThan";
            break;
            
        default:
            return @"UNSUPPORTED_MATCH_TYPE";
            break;
    }
}


+ (NSString*)nativeEqualityRuleEquivalence:(eODEqualityRule)equalityRule
{
    switch (equalityRule) {
        case eODEqualityRuleNone:
            return @"none";
            break;
        case eODEqualityRuleCaseIgnore:
            return @"caseIgnore";
            break;
        case eODEqualityRuleCaseExact:
            return @"caseExact";
            break;
        case eODEqualityRuleNumber:
            return @"number";
            break;
        case eODEqualityRuleCertificate:
            return @"certificate";
            break;
        case eODEqualityRuleTime:
            return @"time";
            break;
        case eODEqualityRuleTelephoneNumber:
            return @"telephoneNumber";
            break;
        case eODEqualityRuleOctetMatch:
            return @"octetMatch";
            break;
            
        default:
            return @"UNSUPPORTED_EQUALITY_TYPE";
            break;
    }
    
}

+ (NSDictionary*)nativePredicateEquivalence:(NSDictionary *)odPredicate
{
    /*
     * Single-Predicate keys:
     *     kODKeyPredicateStdRecordType - The standard OD type for this predicate
     *     kODKeyPredicateRecordType - The native record type for this module
     *     kODKeyPredicateAttribute - The native attribute to be queried
     *     kODKeyPredicateValueList - The values being queried
     *     kODKeyPredicateMatchType - Is the eODMatchType requested by the client (i.e., eODMatchTypeAll, eODMatchTypeEqualTo, etc.)
     *     kODKeyPredicateEquality - Is the eODEqualityRule dictated by the schema (i.e., eODEqualityRuleCaseIgnore, eODEqualityRuleNumber, etc.)
     *
     * Multi-predicate keys:
     *     kODKeyPredicateList - an array of "Single-Predicate" entries
     *     kODKeyPredicateOperator - How the sub-predicates should be evaluated (kODPredicateOperatorAnd, kODPredicateOperatorOr, etc.)
     */

    NSMutableDictionary *nativePredicate = [NSMutableDictionary new];
    NSArray *subODPredicates = [odPredicate objectForKey:[NSString stringWithUTF8String:kODKeyPredicateList]];
    if (subODPredicates) {
        NSString *nativePredicateOperator = nil;
        NSString *odPredicateOperator = [odPredicate objectForKey:[NSString stringWithUTF8String:kODKeyPredicateOperator]];
        if ([odPredicateOperator isEqualToString:[NSString stringWithUTF8String:kODPredicateOperatorOr]]) {
            nativePredicateOperator = @"OR";
        } else if ([odPredicateOperator isEqualToString:[NSString stringWithUTF8String:kODPredicateOperatorAnd]]) {
            nativePredicateOperator = @"AND";
        } else if ([odPredicateOperator isEqualToString:[NSString stringWithUTF8String:kODPredicateOperatorNot]]) {
            nativePredicateOperator = @"NOT";
        }
        
        [nativePredicate setValue:nativePredicateOperator forKey:@"operator"];
        NSString *recordType = [odPredicate objectForKey:[NSString stringWithUTF8String:kODKeyPredicateRecordType]];
        [nativePredicate setValue:recordType forKey:@"recordType"];
        
        NSMutableArray *subNativePredicates = [NSMutableArray new];
        for (NSDictionary *subODPredicate in subODPredicates) {
            NSMutableDictionary *updatedODPredicate = [subODPredicate mutableCopy];
            [updatedODPredicate setObject:recordType forKey:[NSString stringWithUTF8String:kODKeyPredicateRecordType]];
            [subNativePredicates addObject:[self nativePredicateEquivalence:updatedODPredicate]];
        }
        
        [nativePredicate setValue:subNativePredicates forKey:@"predicateList"];

    } else {
        NSString *recordType = [odPredicate objectForKey:[NSString stringWithUTF8String:kODKeyPredicateRecordType]];
        [nativePredicate setValue:recordType forKey:@"recordType"];
        [nativePredicate setValue:[[self sharedInstance] nativeAttrbuteForNativeType:recordType relatedToStandardAttribute:[odPredicate objectForKey:[NSString stringWithUTF8String:kODKeyPredicateStdAttribute]]] forKey:@"attribute"];
        [nativePredicate setValue:[odPredicate objectForKey:[NSString stringWithUTF8String:kODKeyPredicateValueList]] forKey:@"valueList"];
        [nativePredicate setValue:[self nativeMatchTypeEquivalence:[[odPredicate objectForKey:[NSString stringWithUTF8String:kODKeyPredicateMatchType]] intValue]] forKey:@"matchType"];
        [nativePredicate setValue:[self nativeEqualityRuleEquivalence:[[odPredicate objectForKey:[NSString stringWithUTF8String:kODKeyPredicateEquality]] intValue]] forKey:@"equalityRule"];
    }
    
    return nativePredicate;
}

+ (NSArray*)nativePredicatesEquivalence:(NSArray *)odPredicates
{
    NSMutableArray *nativePredicates = [NSMutableArray new];
    
    for (NSDictionary *odPredicate in odPredicates) {
        [nativePredicates addObject:[self nativePredicateEquivalence:odPredicate]];
    }
    
    return nativePredicates;
}
@end
