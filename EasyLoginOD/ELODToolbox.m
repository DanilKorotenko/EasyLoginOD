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

@end
