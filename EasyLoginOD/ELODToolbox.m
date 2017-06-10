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
    
    [translatedInfo setObject:@[nativeType] forKey:kODAttributeTypeRecordType];
    
    // Then start the dance, first we look at native keys available in the current context
    for (NSString *nativeKeyToTranslate in [nativeInfo allKeys]) {
        
        // Then for each native key we found in the provided context, we look at standard who can be built with
        NSSet *relatedStandardKeys = [standardToNativeAttributesMap keysOfEntriesPassingTest:^BOOL(id  _Nonnull key, NSString *  _Nonnull obj, BOOL * _Nonnull stop) {
            return [obj isEqualToString:nativeKeyToTranslate];
        }];
        
        for (NSString *standardKey in relatedStandardKeys) {
            
            NSMutableArray *valuesForStandardKey = [NSMutableArray new];
            
            id nativeValue = [nativeInfo objectForKey:nativeKeyToTranslate];
            
            if ([nativeValue isKindOfClass:[NSArray class]]) {
                NSArray *values = nativeValue;
                [valuesForStandardKey addObjectsFromArray:values];
            } else {
                [valuesForStandardKey addObject:nativeValue];
            }
            
            [translatedInfo setObject:valuesForStandardKey forKey:standardKey];
        }
    }
    
    return translatedInfo;
}

- (NSString*)nativeAttrbuteForNativeType:(NSString *)nativeType relatedToStandardAttribute:(NSString*)standardAttribute {
    return [[[self.mapping objectForKey:nativeType] objectForKey:kEasyLoginMappingInfosStandardToNativeKey] objectForKey:standardAttribute];
}

- (NSArray*)allNativeAttributeSupportedForType:(NSString *)nativeType {
    return [[[self.mapping objectForKey:nativeType] objectForKey:kEasyLoginMappingInfosStandardToNativeKey] allValues];
}

@end
