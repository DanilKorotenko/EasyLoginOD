//
//  ELODToolbox.m
//  EasyLoginOD
//
//  Created by Yoann Gini on 05/06/2017.
//  Copyright © 2017 Yoann Gini (Open Source Project). All rights reserved.
//

#import "ELODToolbox.h"

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
- (NSDictionary*)standardInfoFromNativeInfos:(NSDictionary*)nativeInfo ofType:(NSString *)nativeType {
    // We recieve a native type and a bunch of native key/value or key/[values] that we need to translate to standard key/[value] record
    
    // We load the related translation table that can link a standard key to one or mulitple native key in a specific order
    NSDictionary *standardToNativeAttributesMap = [[self.mapping objectForKey:nativeType] objectForKey:kEasyLoginMappingInfosStandardToNativeKey];
    
    // We create a copy of the existing info to preload the returned one. To fit native and standard info in the same dict.
    NSMutableDictionary *translatedInfo = [NSMutableDictionary new];
    
    // Then start the dance, first we look at native keys available in the current context
    for (NSString *nativeKeyToTranslate in [nativeInfo allKeys]) {
        
        // Then for each native key we found in the provided context, we look at standard who can be built with
        NSSet *relatedStandardKeys = [standardToNativeAttributesMap keysOfEntriesPassingTest:^BOOL(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            if ([obj isKindOfClass:[NSString class]]) {
                NSString *strObj = obj;
                return [strObj isEqualToString:nativeKeyToTranslate];
            } else {
                NSArray *listObj = obj;
                return [listObj containsObject:nativeKeyToTranslate];
            }
        }];
        
        for (NSString *standardKey in relatedStandardKeys) {
            // Once we have the related standard key, we look if the standard attribute use one or many native attribute
            id counterpart = [standardToNativeAttributesMap objectForKey:standardKey];
            
            NSMutableArray *valuesForStandardKey = [NSMutableArray new];
            NSArray *nativeKeysToLoad = nil;
            
            // If it use a single one, we transform it in a array to siplify our work
            if ([counterpart isKindOfClass:[NSString class]]) {
                nativeKeysToLoad = [NSArray arrayWithObject:counterpart];
            } else {
                nativeKeysToLoad = counterpart;
            }
            
            
            for (NSString *nativeKeyToLoad in nativeKeysToLoad) {
                // For each native key we need to know if the provided value is already an array or a single value
                // All standard attribute returned must be wrapped in arrays even if not supposed to be multiple
                
                id nativeValue = [nativeInfo objectForKey:nativeKeyToLoad];
                
                if ([nativeValue isKindOfClass:[NSArray class]]) {
                    NSArray *values = nativeValue;
                    [valuesForStandardKey addObjectsFromArray:values];
                } else {
                    [valuesForStandardKey addObject:nativeValue];
                }
            }
            
            [translatedInfo setObject:valuesForStandardKey forKey:standardKey];
        }
    }
    
    return translatedInfo;
}

@end
