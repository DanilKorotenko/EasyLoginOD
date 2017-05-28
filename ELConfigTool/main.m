//
//  main.m
//  ELConfigTool
//
//  Created by Yoann Gini on 26/05/2017.
//  Copyright © 2017 EasyLogin. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <OpenDirectory/OpenDirectory.h>

@protocol ELConfigCommand <NSObject>

- (BOOL)run;

@end

@interface ELConfigSet : NSObject <ELConfigCommand>

@end

@implementation ELConfigSet

- (BOOL)run {
    NSLog(@"EL ELConfigSet");
	ODConfiguration *odConfig = [ODConfiguration configuration];
    
    if (!odConfig) {
        NSLog(@"EL Unable to get current OD Config");
        return NO;
    } else {
        NSLog(@"EL OD Config loaded %@", odConfig);
    }
    
    ODModuleEntry *odModuleEntry = [ODModuleEntry moduleEntryWithName:@"EasyLogin" xpcServiceName:@"io.easylogin.EasyLoginOD"];

    if (!odModuleEntry) {
        NSLog(@"EL Unable to load new instance of OD Module io.easylogin.EasyLoginOD");
        return NO;
    } else {
        NSLog(@"EL OD Module loaded %@", odModuleEntry);
    }
    
    ODSession *odSession = [ODSession defaultSession];
    
    if (!odSession) {
        NSLog(@"EL Unable to get access to local OD");
        return NO;
    } else {
        NSLog(@"EL OD Session loaded %@", odSession);
    }
    
    NSError *error = nil;
    SFAuthorization *sfAuth = [odSession configurationAuthorizationAllowingUserInteraction:YES error:&error];
    
    if (!sfAuth) {
        NSLog(@"EL Unable to get interactive OD session:\n%@", error);
        return NO;
    } else {
        NSLog(@"EL Auth OK %@", sfAuth);
    }

    odConfig.queryTimeoutInSeconds = 30;
    odConfig.connectionIdleTimeoutInSeconds = 120;
    odConfig.connectionSetupTimeoutInSeconds = 15;

    ODMappings *odMaps = [ODMappings mappings];
    odConfig.defaultMappings = odMaps;
    
    NSArray *mapList = @[
                         
                         // Users
                         @{
                             @"EL_native_type": @"CloudUser",
                             @"EL_std_type": kODRecordTypeUsers,
                             @"EL_attribute_mapping": @{
                                     kODAttributeTypeRecordType: @"type",
                                     
                                     kODAttributeTypeGUID: @"uuid",
                                     kODAttributeTypeUniqueID: @"uid",
                                     kODAttributeTypePrimaryGroupID: @"primarygroup", // should be hard linked to staff for macOS
                                     
                                     kODAttributeTypeRecordName: @"shortname",
                                     kODAttributeTypeComment: @"description",
                                     kODAttributeTypeCreationTimestamp: @"creationdate", // YYYYMMDDHHMMSSZ
                                     kODAttributeTypeModificationTimestamp: @"modificationdate", // YYYYMMDDHHMMSSZ
                                     
                                     kODAttributeTypeFullName: @"displayname",
                                     kODAttributeTypeLastName: @"lastname",
                                     kODAttributeTypeFirstName: @"firstname",
                                     kODAttributeTypeMiddleName: @"middlename",
                                     kODAttributeTypeNamePrefix: @"prefix",
                                     kODAttributeTypeNickName: @"nickname",
                                     kODAttributeTypeBirthday: @"birthday",
                                     kODAttributeTypeEMailAddress: @"email",
                                     kODAttributeTypeJPEGPhoto: @"photo",
                                     kODAttributeTypeAuthenticationHint: @"passwordhint",
                                     kODAttributeTypeWeblogURI: @"blog",
                                     
                                     kODAttributeTypeFaxNumber: @"fax",
                                     kODAttributeTypePhoneNumber: @"phone",
                                     kODAttributeTypeMobileNumber: @"mobilephone",
                                     kODAttributeTypeHomePhoneNumber: @"personalphone",
                                     kODAttributeTypeIMHandle: @"instantmessaging",
                                     kODAttributeTypePagerNumber: @"pager",

                                     kODAttributeTypeAddressLine1: @"addresline1",
                                     kODAttributeTypeAddressLine2: @"addresline2",
                                     kODAttributeTypeAddressLine3: @"addresline3",
                                     kODAttributeTypeState: @"state",
                                     kODAttributeTypeStreet: @"street",
                                     kODAttributeTypeAreaCode: @"areacode",
                                     kODAttributeTypeBuilding: @"building",
                                     kODAttributeTypeCity: @"city",
                                     kODAttributeTypeCompany: @"company",
                                     kODAttributeTypeCountry: @"country",
                                     kODAttributeTypeDepartment: @"department",
                                     kODAttributeTypeJobTitle: @"jobtitle",
                                     kODAttributeTypeOrganizationInfo: @"organizationinfo",
                                     kODAttributeTypeOrganizationName: @"organizationname",
                                     
                                     kODAttributeTypeUserSMIMECertificate: @"publicmailcert",
                                     kODAttributeTypeUserCertificate: @"internalcert",
                                     kODAttributeTypeUserPKCS12Data: @"pkcs12",
                                     kODAttributeTypePGPPublicKey: @"pgppublickey",
                                     
                                     kODAttributeTypeUserShell: @"shell",
                                     kODAttributeTypeHomeDirectory: @"home",
                                     kODAttributeTypeHomeDirectoryQuota: @"homehardquota",
                                     kODAttributeTypeHomeDirectorySoftQuota: @"homesoftquota",
                                     },
                             },
                         
                         
                         // Groups
                         @{
                             @"EL_native_type": @"CloudGroup",
                             @"EL_std_type": kODRecordTypeGroups,
                             @"EL_attribute_mapping": @{
                                     kODAttributeTypeFullName: @"common_name",
                                     kODAttributeTypeRecordName: @"shortname",
                                     kODAttributeTypeGUID: @"uuid",
                                     },
                             },
                         
                         ];
    
    for (NSDictionary *mapInfo in mapList) {
        ODRecordMap *recordMap = [ODRecordMap recordMap];
        recordMap.native = [mapInfo objectForKey:@"EL_native_type"];
        
        NSDictionary *attributeMap = [mapInfo objectForKey:@"EL_attribute_mapping"];
        
        for (NSString *key in [attributeMap allKeys]) {
                [recordMap setAttributeMap:[ODAttributeMap attributeMapWithValue:[attributeMap objectForKey:key]] forStandardAttribute:key];
        }
        
        [odMaps setRecordMap:recordMap forStandardRecordType:[mapInfo objectForKey:@"EL_std_type"]];
    }
    
    odConfig.defaultModuleEntries = @[odModuleEntry];
    odConfig.comment = @"Cloud Directory Service module for Open Directory.";
    odConfig.nodeName = @"/EasyLogin";

    BOOL success = [odSession addConfiguration:odConfig authorization:sfAuth error:&error];

    if (!success) {
        NSLog(@"EL Add config failed with error:\n%@", error);
    }
    return success;
}

@end

@interface ELConfigUnset : NSObject <ELConfigCommand>

@end

@implementation ELConfigUnset

- (BOOL)run {
    NSLog(@"EL ELConfigUnset");
    ODConfiguration *odConfig = [ODConfiguration configuration];
    
    if (!odConfig) {
        NSLog(@"EL Unable to get current OD Config");
        return NO;
    } else {
        NSLog(@"EL OD Config loaded %@", odConfig);
    }
    
    ODModuleEntry *odModuleEntry = [ODModuleEntry moduleEntryWithName:@"EasyLogin" xpcServiceName:@"io.easylogin.EasyLoginOD"];
    
    if (!odModuleEntry) {
        NSLog(@"EL Unable to load new instance of OD Module io.easylogin.EasyLoginOD");
        return NO;
    } else {
        NSLog(@"EL OD Module loaded %@", odModuleEntry);
    }
    
    ODSession *odSession = [ODSession defaultSession];
    
    if (!odSession) {
        NSLog(@"EL Unable to get access to local OD");
        return NO;
    } else {
        NSLog(@"EL OD Session loaded %@", odSession);
    }
    
    NSError *error = nil;
    SFAuthorization *sfAuth = [odSession configurationAuthorizationAllowingUserInteraction:YES error:&error];
    
    if (!sfAuth) {
        NSLog(@"EL Unable to get interactive OD session:\n%@", error);
        return NO;
    } else {
        NSLog(@"EL Auth OK %@", sfAuth);
    }
    
    BOOL success = [odSession deleteConfigurationWithNodename:@"/EasyLogin" authorization:sfAuth error:&error];
    
    if (!success) {
        NSLog(@"EL Delete config failed with error:\n%@", error);
    }
    return success;
}

@end

int main(int argc, const char * argv[]) {
    int exitCode = EXIT_FAILURE;
    @autoreleasepool {
        id<ELConfigCommand> command;
        NSLog(@"EL Starting process");
        exitCode = EXIT_SUCCESS;
        if ( (argc == 2) && (strcmp(argv[1], "set") == 0) ) {
            command = [ELConfigSet new];
        } else if ( (argc == 2) && (strcmp(argv[1], "unset") == 0) ) {
            command = [ELConfigUnset new];
        } else {
            exitCode = EXIT_FAILURE;
        }
        
        if (exitCode == EXIT_FAILURE) {
            fprintf(stderr, "usage: %s set\n", getprogname());
            fprintf(stderr, "usage: %s unset\n", getprogname());
        } else {
            exitCode = [command run] ? EXIT_SUCCESS : EXIT_FAILURE;
        }
    }
    return exitCode;
}
