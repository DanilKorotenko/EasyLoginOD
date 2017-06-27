//
//  Configuration.m
//  EasyLoginOD
//
//  Created by Yoann Gini on 28/05/2017.
//  Copyright © 2017 Yoann Gini (Open Source Project). All rights reserved.
//

#import "Configuration.h"
#import <OpenDirectory/OpenDirectory.h>
#import <Cocoa/Cocoa.h>

#import "Common.h"

#import <EasyLogin/EasyLogin.h>
#include <libkern/OSAtomic.h>

@interface Configuration ()

@property ODSession *odSession;
@property SFAuthorization *sfAuth;

@property NSString *action;

@property NSString *host;
@property NSInteger port;

@property NSInteger queryTimeout;
@property NSInteger idleTimeout;
@property NSInteger setupTimeout;

@end

@implementation Configuration

- (instancetype)init
{
    self = [super init];
    if (self) {
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{
                                                                  @"queryTimeout": @30,
                                                                  @"idleTimeout": @120,
                                                                  @"setupTimeout": @15,
                                                                  }];
        
        _action = [[NSUserDefaults standardUserDefaults] stringForKey:@"action"];
        
        _queryTimeout = [[NSUserDefaults standardUserDefaults] integerForKey:@"queryTimeout"];
        _idleTimeout = [[NSUserDefaults standardUserDefaults] integerForKey:@"idleTimeout"];
        _setupTimeout = [[NSUserDefaults standardUserDefaults] integerForKey:@"setupTimeout"];

    }
    return self;
}

- (int)run {
    int returnedStatus = [self checkCommonRequierements];
    
    if (EXIT_SUCCESS != returnedStatus) {
        return returnedStatus;
    }
    
    if ([@"load" isEqualToString:self.action]) {
        return [self runLoadAction];
        
    }
    else if ([@"unload" isEqualToString:self.action]) {
        return [self runUnloadAction];
        
    }
    
    [self showHelpAsError:NO];
    
    return EXIT_FAILURE;
}

- (NSString*)nodeMountPath {
    return [NSString stringWithFormat:@"/EasyLogin"];
}

- (int)checkCommonRequierements {
    self.odSession = [ODSession defaultSession];
    
    if (!self.odSession) {
        fprintf(stderr, "EasyLogin were unable to create a new OD session\n");
        return EXIT_FAILURE;
    }
    
    NSError *error = nil;
    self.sfAuth = [self.odSession configurationAuthorizationAllowingUserInteraction:YES error:&error];
    
    if (!self.sfAuth) {
        fprintf(stderr, "EasyLogin were unable to get an authorized OD session:\n%s\n", [[error description] UTF8String]);
        return EXIT_FAILURE;
    }
    
    return EXIT_SUCCESS;
}

- (int)runLoadAction {
    ODConfiguration *odConfig = [ODConfiguration configuration];
    
    if (!odConfig) {
        fprintf(stderr, "EasyLogin were unable create new OD config. Your system must be almost dead.\n");
        return EXIT_FAILURE;
    }
    
    odConfig.queryTimeoutInSeconds = self.queryTimeout;
    odConfig.connectionIdleTimeoutInSeconds = self.idleTimeout;
    odConfig.connectionSetupTimeoutInSeconds = self.setupTimeout;
    
    ODMappings *odMaps = [ODMappings mappings];
    odConfig.defaultMappings = odMaps;
    
    NSString *odModulePath = [NSString stringWithFormat:@"/Library/OpenDirectory/Modules/%@.xpc/Contents/Resources/ELMapping.plist", kEasyLoginODModuleBundleName];
    
    NSDictionary *mappingInfos = [NSDictionary dictionaryWithContentsOfFile:odModulePath];
    
    for (NSString *nativeType in [mappingInfos allKeys]) {
        NSDictionary *mapInfos = [mappingInfos objectForKey:nativeType];
        NSString *standardType = [mapInfos objectForKey:kEasyLoginMappingInfosStandardTypeKey];
        
        ODRecordMap *recordMap = [ODRecordMap recordMap];
        recordMap.native = nativeType;
        
        NSDictionary *standardToNativeAttributesMap = [mapInfos objectForKey:kEasyLoginMappingInfosStandardToNativeKey];
        
        for (NSString *standardAttributeType in [standardToNativeAttributesMap allKeys]) {
            id nativeCounterpart = [standardToNativeAttributesMap objectForKey:standardAttributeType];
            
            ODAttributeMap *attributeMap = [ODAttributeMap attributeMapWithValue:nativeCounterpart];
//            attributeMap.customTranslationFunction = [NSString stringWithFormat:@"%@:translate_attribute", kEasyLoginODModuleBundleName];
            
            [recordMap setAttributeMap:attributeMap
                  forStandardAttribute:standardAttributeType];
        }
        
        [odMaps setRecordMap:recordMap forStandardRecordType:standardType];
    }
    
    ODModuleEntry *odModuleEntry = [ODModuleEntry moduleEntryWithName:kEasyLoginODModuleEntryName xpcServiceName:kEasyLoginODModuleBundleName];
        
    if (!odModuleEntry) {
        fprintf(stderr, "EasyLogin were unable to load new instance of OD Module %s. Check content of OD Module folder.\n", [kEasyLoginODModuleIdentifier UTF8String]);
        return EXIT_FAILURE;
    }
    
    odConfig.defaultModuleEntries = @[odModuleEntry];
    odConfig.comment = @"EasyLogin module for Open Directory.";
    odConfig.nodeName = [self nodeMountPath];
    
    NSError *error = nil;
    
    if (![self.odSession addConfiguration:odConfig authorization:self.sfAuth error:&error]) {
        fprintf(stderr, "EasyLogin were unable to load new configuration, error:\n%s\n", [[error description] UTF8String]);
        return EXIT_FAILURE;
    }

    return EXIT_SUCCESS;
}

- (int)runUnloadAction {
    NSError *error = nil;
    
    if (![self.odSession deleteConfigurationWithNodename:[self nodeMountPath] authorization:self.sfAuth error:&error]) {
        fprintf(stderr, "EasyLogin were unable to delete configuration, error:\n%s\n", [[error description] UTF8String]);
        return EXIT_FAILURE;
    }
    
    return EXIT_SUCCESS;
}

- (void)showHelpAsError:(BOOL)helpAsError {
    FILE * __restrict output = helpAsError ? stderr : stdout;
    const char *command = getprogname();
    
    fprintf(stderr, "usage: %s -action < load | unload >\n", command);
    fprintf(output, "\n");
    
    fprintf(stderr, "%s -action load\n", command);
    fprintf(stderr, "\tLoad the EasyLogin OD module.\n");
    fprintf(stderr, "\tServer to use will be found the in the io.easylogin.settings preferences' domain.\n");
    fprintf(output, "\n");
    
    fprintf(stderr, "%s -action unload\n", command);
    fprintf(stderr, "\tUnload the EasyLogin OD module.\n");
    fprintf(output, "\n");
}

@end
