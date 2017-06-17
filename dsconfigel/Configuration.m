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
                                                                  @"port": @443,
                                                                  @"queryTimeout": @30,
                                                                  @"idleTimeout": @120,
                                                                  @"setupTimeout": @15,
                                                                  }];
        
        _action = [[NSUserDefaults standardUserDefaults] stringForKey:@"action"];
        _host = [[NSUserDefaults standardUserDefaults] stringForKey:@"host"];
        _port = [[NSUserDefaults standardUserDefaults] integerForKey:@"port"];
        
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
    
    if ([@"join" isEqualToString:self.action]) {
        return [self runJoinAction];
        
    } else if ([@"leave" isEqualToString:self.action]) {
        return [self runLeaveAction];
        
    } else if ([@"update" isEqualToString:self.action]) {
        return [self runUpdateAction];
        
    } else if ([@"show" isEqualToString:self.action]) {
        return [self runShowAction];
        
    } else if ([@"synced" isEqualToString:self.action]) {
        return [self runSyncedAction];
    }
    
    [self showHelpAsError:NO];
    
    return EXIT_FAILURE;
}

- (NSString*)nodeMountPath {
    return [NSString stringWithFormat:@"/EasyLogin"];
}

- (int)checkCommonRequierements {
    
    if (![@[@"join", @"leave", @"update", @"show", @"synced"] containsObject:self.action]) {
        fprintf(stderr, "You must specify an action to run this tool\n");
        
        [self showHelpAsError:YES];
        
        return EXIT_FAILURE;
    }
    
    if (![@[@"show", @"synced"] containsObject:self.action]) {
        if ([self.host length] == 0) {
            fprintf(stderr, "You must specify a target host to run this action\n");
            
            [self showHelpAsError:YES];
            
            return EXIT_FAILURE;
        }
        
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
    }
    
    return EXIT_SUCCESS;
}

- (int)runJoinAction {
    ODConfiguration *odConfig = [ODConfiguration configuration];
    
    if (!odConfig) {
        fprintf(stderr, "EasyLogin were unable create new OD config. Your system must be almost dead.\n");
        return EXIT_FAILURE;
    }
    
    odConfig.queryTimeoutInSeconds = self.queryTimeout;
    odConfig.connectionIdleTimeoutInSeconds = self.idleTimeout;
    odConfig.connectionSetupTimeoutInSeconds = self.setupTimeout;
    
    odConfig.preferredDestinationHostName = self.host;
    odConfig.preferredDestinationHostPort = self.port;
    
    ODMappings *odMaps = [ODMappings mappings];
//    odMaps.function = [NSString stringWithFormat:@"%@:translate_recordtype", kEasyLoginODModuleBundleName];
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

- (int)runLeaveAction {
    NSError *error = nil;
    
    if (![self.odSession deleteConfigurationWithNodename:[self nodeMountPath] authorization:self.sfAuth error:&error]) {
        fprintf(stderr, "EasyLogin were unable to delete configuration, error:\n%s\n", [[error description] UTF8String]);
        return EXIT_FAILURE;
    }
    
    return EXIT_SUCCESS;
}

- (int)runUpdateAction {
    return EXIT_FAILURE;
}

- (int)runShowAction {
    return EXIT_FAILURE;
}

- (int)runSyncedAction {
    __block OSSpinLock waitForAsync = OS_SPINLOCK_INIT;
    
    NSString *uuid = [[NSUserDefaults standardUserDefaults] stringForKey:@"uuid"];
    
    if ([uuid  length] > 0) {
        OSSpinLockLock(&waitForAsync);
        [[EasyLoginDBProxy sharedInstance] getRegisteredRecordOfType:@"user" withUUID:uuid andCompletionHandler:^(NSDictionary *record, NSError *error) {
            fprintf(stdout, "%s\n", [[record description] UTF8String]);
            OSSpinLockUnlock(&waitForAsync);
            
        }];
    } else {
        OSSpinLockLock(&waitForAsync);
        [[EasyLoginDBProxy sharedInstance] getAllRegisteredRecordsOfType:@"user"
                                                  withAttributesToReturn:@[@"shortname", @"uuid"]
                                                    andCompletionHandler:^(NSArray<NSDictionary *> *results, NSError *error) {
                                                        for (NSDictionary *record in results) {
                                                            fprintf(stdout, "%s\n", [[NSString stringWithFormat:@"- %@ (%@)", [record objectForKey:@"shortname"], [record objectForKey:@"uuid"]] UTF8String]);
                                                        }
                                                        
                                                        OSSpinLockUnlock(&waitForAsync);
                                                    }];
    }
    OSSpinLockLock(&waitForAsync);
    OSSpinLockUnlock(&waitForAsync);
    return EXIT_SUCCESS;
}

- (void)showHelpAsError:(BOOL)helpAsError {
    FILE * __restrict output = helpAsError ? stderr : stdout;
    const char *command = getprogname();
    
    fprintf(stderr, "usage: %s -action < show | join | leave | update | synced > ...\n", command);
    fprintf(output, "\n");
    
    fprintf(stderr, "%s -action show\n", command);
    fprintf(stderr, "\tDisplay current configuration\n");
    fprintf(output, "\n");
    
    fprintf(stderr, "%s -action join -host %s ...\n", command, [kEasyLoginSampleServer UTF8String]);
    fprintf(stderr, "\tBind to target EasyLogin server.\n");
    fprintf(stderr, "\tIf an authentication is requiered by the server,\n\tclient certificate will be looked in system keychain.\n");
    fprintf(output, "\n");
    
    fprintf(stderr, "%s -action leave -host %s\n", command, [kEasyLoginSampleServer UTF8String]);
    fprintf(stderr, "\tLeave the target server\n");
    fprintf(stderr, "\tIf server was using certificate based authentication,\n\tcertificate will stay in system keychain.\n");
    fprintf(output, "\n");
    
    fprintf(stderr, "%s -action update -host %s ...\n", command, [kEasyLoginSampleServer UTF8String]);
    fprintf(stderr, "\tUpdate current configuration settings\n");
    fprintf(output, "\n");
    
    fprintf(stderr, "%s -action synced\n", command);
    fprintf(stderr, "\tList records synced on this computer\n");
    fprintf(output, "\n");
    
    fprintf(stderr, "%s -action synced -uuid aUUIDReturnedByTheSyncedAction\n", command);
    fprintf(stderr, "\tShow raw informations synecd for target UUID\n");
    fprintf(output, "\n");
    
    fprintf(output, "Defaults values for optional arguments in current context are:\n");
    
    NSArray *keys = @[@"port", @"queryTimeout", @"idleTimeout", @"setupTimeout"];
    
    int padLength = 20;
    
    for (NSString *key in keys) {
        int computedLengh = (int)[key length] + 10;
        padLength = computedLengh > padLength ? computedLengh : computedLengh;
    }
    
    for (NSString *key in keys) {
        NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:key];
        int localPad = padLength - (int)[key length];
        
        fprintf(output, "\t-%s %*ld\n", [key UTF8String], localPad, (long)value);
    }
}

@end
