/*
 *  EasyLoginOD.c
 *  EasyLoginOD
 *
 *  Created by Yoann Gini on 26/05/2017.
 *  Copyright © 2017 EasyLogin. All rights reserved.
 *
 */

#include "EasyLoginOD.h"
#include <odmodule/odmodule.h>
#import "ELODToolbox.h"
#import <EasyLogin/EasyLogin.h>


#if __has_feature(objc_arc)
#error OD modules can not be built with ARC enabled.
// In theory OD objects should be like OS objects, and thus compatible
// with ARC.  Alas, there's a bug that prevents this from working
// <rdar://problem/18335730>.  This bug also prevents you reverting to manual
// memory management for OD objects while keeping ARC for all your other
// Objective-C and OS object needs.
#endif

/*
 * Open Directory configurations allow for one or more modules to be active.  Each module must return a
 * eODCallbackResponse value as appropriate. There are 4 possible values for eODCallbackResponse:
 *
 *     eODCallbackResponseSkip -- skip this module, go to next module (if present)
 *     eODCallbackResponseAccepted -- has been accepted and this module will respond
 *     eODCallbackResponseForward -- request was modified, forward to next module (not common)
 *     eODCallbackResponseRefused -- will reply to the client that the operation is unsupported
 *
 * There is a logging design that ties all log messages to a specific request, whether it is internally or client
 * generated.  Messages can be logged using:
 *
 *     	odrequest_log_message(request, <loglevel>, <format string or message>, <parameters for the format string>);
 *
 * Log levels mirror syslog-style log messages.  Note that only errors are logged by default.  Logging level can be
 * changed using "odutil set log <level>" and will be logged to "/var/log/opendirectoryd.log".
 *
 * The current log level can be checked using 'log_level_enabled' to avoid expensive work when a log level
 * is not enabled:
 *
 *     if (log_level_enabled(<level>)) {
 *         // do work
 *     }
 *
 * Possible levels include:
 *
 *     eODLogCritical -- redirects to system.log as well
 *     eODLogError    -- some error occurred (this is the default logging level)
 *     eODLogWarning  -- concerning, but not fatal
 *     eODLogNotice   -- normal log details for high-level information, this should be minimal information
 *     eODLogInfo     -- some information info (like connection checks, scans, etc.)
 *     eODLogDebug    -- full debug information needed to help diagnose involved isues
 *
 * Responding to a request depends on the call being made.  There are several response APIs provided:
 *
 *     odrequest_respond_success
 *     odrequest_respond_error
 *     odrequest_respond_recordcreate
 *     etc.
 */


static od_module_t odmodule;

#pragma mark - Basics

static void ELModuleInit(od_module_t module)
{
    /*
     * This is called only once when the module is first loaded.  Do any global initialization here.
     */
    
    // AH: It seems this method is not called on 10.11 (says ygi). So it seems quite unsafe to use it for init/setup
    
    
    odmodule = module; /* no need to retain this object, it has the lifetime of the service */
    odrequest_log_message(NULL, eODLogInfo, CFSTR("Initialization request recieved"));
}


/*
 * This routine is called whenever a new moduleconfig has been created that references this module.
 * A context can be created/set during this stage by calling odmoduleconfig_set_context.
 */
static void ELConfigLoaded(od_request_t request, od_moduleconfig_t moduleconfig)
{
    
    //	odmoduleconfig_set_context(moduleconfig, myContext, myContextDeallocator)
    
    odrequest_log_message(request, eODLogInfo, CFSTR("Configuration loaded"));
}


/*
 * This routine is called to parse unknown destination strings.  These destinations are triggered by use
 * of DynamicNode configurations.  Typically it'll be the trailing part of a node name, for example:
 *
 *    /LDAPv3/ldap://server.company.com
 *
 * The destination passed to this moduleconfig will be "ldap://server.company.com".  The response from
 * this call should return an XPC_TYPE_DICTIONARY, with 2 keys ("host" and "port") and corresponding values.
 */
//static xpc_object_t
//ELParseDynamicDestination(od_request_t request, od_moduleconfig_t moduleconfig, const char *destination)
//{
//    odrequest_log_message(request, eODLogInfo, CFSTR("Dynamic destination requested"));
//
//    xpc_object_t dict = xpc_dictionary_create(NULL, NULL, 0);
//
//    xpc_dictionary_set_value(dict, "host", xpc_string_create(""));
//    xpc_dictionary_set_int64(dict, "port", 443);
//
//    return dict;
//}


/*! A Open Directory connection reconnect_cb callback function.
 *
 *  See CreateConnection for background.  Because we don't support remote connections,
 *  the implementation here is trivial.
 *
 *  \param connection The connection that should reconnect.
 *  \param request The request that triggered the reconnect.
 *  \param context The connection's context.
 *  \returns An error code.
 */
static uint32_t reconnect_cb(od_connection_t connection, od_request_t request, void *context)
{
    BOOL reconnectOK = YES;
    
    odrequest_log_message(request, eODLogInfo, CFSTR("Connection to database done with %@"), reconnectOK ? CFSTR("success") : CFSTR("failure"));
    
    return reconnectOK ? kODErrorSuccess : kODErrorNodeConnectionFailed;
}



/*! A Open Directory connection disconnect_cb callback function.
 *
 *  See CreateConnection for background.  Because we don't support remote connections,
 *  the implementation here is trivial.
 *
 *  \param connection The connection that should reconnect.
 *  \param sock The connection's socket.
 *  \param context The connection's context.
 */
static void disconnect_cb(od_connection_t connection, __unused int sock, void *context)
{
    odrequest_log_message(NULL, eODLogInfo, CFSTR("Disconnect from database"));
}


/*
 * This is called when a new connection is requested for this moduleconfig.  An appropriate od_connection_t should be returned.
 * Connections are optional for authentication modules, but they are required for all other modules to support queries, modifications
 * and other APIs.  A connection is not required to have an actual network connection, it's mostly used for tracking state, etc.
 *
 * Any option overrides will be passed in the options_dict.  Connections are tracked and idle-disconnected (if an idle disconnect
 * time is set).
 */
static od_connection_t ELCreateConnectionWithOptions(od_request_t request, od_moduleconfig_t moduleconfig, od_credential_t credential, eODModuleConfigServerFlags flags, xpc_object_t option_dict)
{
    int32_t idle_timeout = odmoduleconfig_get_option_int32(moduleconfig, odmodule, CFSTR("connection idle disconnect"), 0);
    od_connection_info_t info = {
        .context = NULL,
        .context_dealloc = NULL,
        .reconnect_cb = reconnect_cb,
        .disconnect_cb = disconnect_cb,
    };
    
    odrequest_log_message(request, eODLogInfo, CFSTR("Creating database connection"));
    
    return odconnection_create_ext(moduleconfig, request, CFSTR("EasyLogin"), NULL, credential, flags, idle_timeout, &info);
}


/*
 * This is called when an ODNodeCopyDetails call is initiated.  Each module must provide necessary details for the connection
 * passed to this routine.  The response must be an XPC_TYPE_DICTIONARY with traditional OpenDirectory attribute strings.
 *
 * The dictionary must contain an array for the associated key.
 */
static xpc_object_t ELCopyDetails(od_request_t request, od_connection_t connection)
{
    odrequest_log_message(request, eODLogInfo, CFSTR("Got request for node info"));
    
    xpc_object_t dict = xpc_dictionary_create(NULL, NULL, 0);
    
    xpc_object_t values = xpc_array_create(NULL, 0);
    xpc_array_set_string(values, XPC_ARRAY_APPEND, "Authenticated");
    xpc_dictionary_set_value(dict, [kODAttributeTypeTrustInformation UTF8String], values);
    
    values = xpc_array_create(NULL, 0);
    xpc_array_set_string(values, XPC_ARRAY_APPEND, [@"EasyLogin" UTF8String]);
    xpc_dictionary_set_value(dict, [kODAttributeTypeAuthMethod UTF8String], values);
    
    return dict;
}


#pragma mark - Authentication callbacks

/*
 * Most authentication callbacks will be passed additional information if available.  That information is determined by the
 * callback "copy_auth_information" and other current information.  The goal is to provide any information from the record that
 * might be needed to service this authentication request.  All information will be passed into the authentication calls,
 * if available, as "addinfo_dict".  The dictionary contains:
 *
 *     kODAuthInfoUserDetails - Is an XPC_TYPE_DICTIONARY of keys related to the user
 *     kODAuthInfoConnectionDestination - Is an XPC_TYPE_DICTIONARY containing the current destination for the session connection
 *                                        which allows for an authentication module to contact the same server.
 *     kODAuthInfoSessionCredentials - Is an XPC_TYPE_DICTIONARY containing the current credentials attached to the session connection,
 *                                     which is servicing the API calls.
 */

static xpc_object_t ELCopyAuthInfo(od_request_t request, od_moduleconfig_t moduleconfig, long info)
{
    xpc_object_t returnValue = NULL;
    
    /*
     * This callback is called to gather information required to perform an authentication request.  This callback
     * is required if the module plans to service authentication requests.
     *
     * There are current 3 types of possible information that can be requested and may be extended
     * in the future.
     */
    
    odrequest_log_message(request, eODLogInfo, CFSTR("Got request for authentication infos"));
    
    switch (info) {
        case eODAuthInfoAttributes:
            /*
             * eODAuthInfoAttributes - Is an array of attributes to be retrieved from a record to perform an authentication.
             *                         This is allows authentication modules to know nothing about an actual record to perform
             *                         an authentication.  Some attributes are retrieved automatically and does not require
             *                         a module to call them out (see list below):
             *
             *                             kODAttributeTypeMetaRecordName
             *                             kODAttributeTypeAuthenticationAuthority
             *                             kODAttributeTypePasswordPolicyOptions
             *                             kODAttributeTypePassword
             *                             kODAttributeTypeGUID
             *                             kODAttributeTypeUniqueID
             *                             kODAttributeTypeRecordType
             */
            returnValue = xpc_array_create(NULL, 0);
            //            			xpc_array_append_cftype(returnValue, kODAttributeTypePrimaryGroupID);
            //            			xpc_array_set_string(returnValue, XPC_ARRAY_APPEND, "dsAttrTypeNative:my_nativeattribute");
            break;
            
        case eODAuthInfoAuthTypes:
            /*
             * eODAuthInfoAuthTypes - An array of authentication types supported by this module.  This is used to preflight
             *                        Authentications so the list must be complete for supported auth types.  For example:
             *
             *                             kODAuthenticationTypeCRAM_MD5
             *                             kODAuthenticationTypeDigest_MD5
             *                             etc.
             */
            returnValue = xpc_array_create(NULL, 0);
            xpc_array_append_cftype(returnValue, kODAuthenticationTypeClearText);
            break;
            
        case eODAuthInfoMechanisms:
            /*
             * eODAuthInfoMechanisms - An array of mechanisms supported by this authentication module.  This corresponds to the
             *                         values in AuthenticationAuthority (e.g., Kerberos, basic, etc.).
             */
            
            returnValue = xpc_array_create(NULL, 0);
            xpc_array_set_string(returnValue, XPC_ARRAY_APPEND, "EasyLogin");
            break;
    }
    
    return returnValue;
}

static eODCallbackResponse ELRecordVerifyPassword(od_request_t request, od_connection_t connection, const char *record_type, const char *metarecordname, const char *recordname, const char *password, xpc_object_t addinfo_dict)
{
    /*
     * This is called to verify a password of a user.  As with other authentication calls, addinfo_dict contains
     * additional information that may be useful to complete the authentication.
     */
    
#warning (ygi) Passwords sent to this method seems to always be in clear text when comming from the loginwindow or the shell. We need to check how this work when using file sharing and screen sharing.
    
    odrequest_log_message(request, eODLogInfo, CFSTR("Password validation requested for `%s` of type `%s`"), recordname, record_type);
    
    [[ELAsyncBlockToManageAsOperation runOnSharedQueueOperationWithAsyncTask:^(ELAsyncBlockToManageAsOperation *currentOperation) {
        [[ELCachingDBProxy sharedInstance] getRegisteredRecordUUIDsOfType:[NSString stringWithUTF8String:record_type]
                                                    matchingAllAttributes:@{@"shortname": [NSString stringWithUTF8String:recordname]}
                                                     andCompletionHandler:^(NSArray<NSString *> *results, NSError *error) {
                                                         if (error != nil || [results count] != 1) {
                                                             odrequest_log_message(request, eODLogError, CFSTR("Unexpected error when retriving record of type `%s` with recordname `%s`: %@"), record_type, recordname, error);
                                                             odrequest_respond_error(request, kODErrorCredentialsServerError, NULL);
                                                         } else {
                                                             if ([results count] == 1) {
                                                                 odrequest_log_message(request, eODLogInfo, CFSTR("Requested record found, now looking for authentication infos"));
                                                                 
                                                                 NSString *userUUID = [results lastObject];
                                                                 
                                                                 [[ELAsyncBlockToManageAsOperation runOnSharedQueueOperationWithAsyncTask:^(ELAsyncBlockToManageAsOperation *currentOperation) {
                                                                     [[ELCachingDBProxy sharedInstance] getRegisteredRecordOfType:[NSString stringWithUTF8String:record_type]
                                                                                                                         withUUID:userUUID
                                                                                                             andCompletionHandler:^(NSDictionary *record, NSError *error) {
                                                                                                                 if (error) {
                                                                                                                     odrequest_log_message(request, eODLogError, CFSTR("Unexpected error when retriving record for user `%s`: %@"), recordname, error);
                                                                                                                     odrequest_respond_error(request, kODErrorCredentialsServerError, NULL);
                                                                                                                 } else {
                                                                                                                     odrequest_log_message(request, eODLogInfo, CFSTR("Authentication infos found, validating password"));
                                                                                                                     
                                                                                                                     if ([[ELODToolbox sharedInstance] validatePassword:[NSString stringWithUTF8String:password]
                                                                                                                                           againstAuthenticationMethods:[record objectForKey:@"authMethods"]]) {
                                                                                                                         odrequest_log_message(request, eODLogInfo, CFSTR("Authentication done with success"));
                                                                                                                         odrequest_respond_error(request, kODErrorSuccess, NULL);
                                                                                                                     } else {
                                                                                                                         odrequest_log_message(request, eODLogInfo, CFSTR("Authentication done with failure"));
                                                                                                                         odrequest_respond_error(request, kODErrorCredentialsInvalid, NULL);
                                                                                                                     }
                                                                                                                 }
                                                                                                                 [currentOperation considerThisOperationAsDone];
                                                                                                             }];
                                                                     
                                                                 }
                                                                                                                   withCancelationHandler:nil
                                                                                                                              andUserInfo:nil]waitUntilFinished];
                                                                 
                                                             } else {
                                                                 odrequest_log_message(request, eODLogError, CFSTR("Got %lu record of type `%s` with recordname `%s`, this is uncompatible with an authentication request"), (unsigned long)[results count], record_type, recordname);
                                                             }
                                                         }
                                                         
                                                         [currentOperation considerThisOperationAsDone];
                                                     }];
        
    }
                                                      withCancelationHandler:nil
                                                                 andUserInfo:nil] waitUntilFinished];
    
    
    
    
    
    return eODCallbackResponseAccepted;
}

//static eODCallbackResponse ELRecordVerifyPasswordExtended(od_request_t request, od_connection_t connection, const char *record_type, const char *metarecordname, const char *recordname, const char *auth_type, eODAuthType od_auth_type,
//                                                          xpc_object_t auth_items, od_context_t auth_context, xpc_object_t addinfo_dict)
//{
//    /*
//     * This is called to verify a password of a user for multi-pass authentications.  As with other authentication calls, addinfo_dict contains
//     * additional information that may be useful to complete the authentication.  Not all methods will provide additional information.
//     */
//
//    //	od_context_t context = odcontext_create(request, myContext, context_deallocator);
//    //
//    //	/* do some work and respond with a context accordingly */
//    //
//    //	return odrequest_respond_authentication_continuation(request, auth_ctx, result_array);
//
//    odrequest_log_message(request, eODLogInfo, CFSTR("Extended password validation of type `%s` requested for `%s` of type `%s`"), auth_type, recordname, record_type);
//
//    return eODCallbackResponseSkip;
//}

static eODCallbackResponse ELRecordChangePassword(od_request_t request, od_connection_t connection, const char *record_type, const char *metarecordname, const char *recordname, const char *old_password, const char *new_password, xpc_object_t addinfo_dict)
{
    /*
     * This is called to change the password of a user.  The current and new password are passed to the call.  If no previous password is provided, then
     * the existing connection credentials should be used to attempt the password change.  An appropriate error should be returned if necessary.
     */
    
    odrequest_log_message(request, eODLogInfo, CFSTR("Password change requested for `%s` of type `%s`"), recordname, record_type);
    
    return eODCallbackResponseSkip;
}

#pragma mark - Query support

/*! Called by OD when the last reference to an od_context_t is released.
 *  This is the module's opportunity to release any information about that context.
 *  In our case the context is just an Objective-C object, so we release that.
 *
 *  \param context The (void *) associated with the context.
 */

static void ELReleaseOperationFromQueryContext(void *context)
{
    // We don't provide context info for now
}

/*
 * There are 2 types of query callbacks, only one should be implemented.  One supports OD-style predicates, the other is
 * a very simple query that handles the complex predicate logic.  Predicate queries handle the start, response(s) and end.
 * Simple queries just need to return results directly and a higher-level will handle the wrapping of the query.
 *
 * Predicate queries should support a concept of cancellation and synchronization.  Simple queries are limited
 * and can only be canceled after the current simple-query is complete.
 */

static eODCallbackResponse ELQueryCreateWithPredicates(od_request_t request, od_connection_t connection, xpc_object_t predicate, int32_t maxResults, int32_t pageSize, xpc_object_t returnAttributes)
{
    /*
     * This uses a new ODPredicate format that allows for more complex queries to be formed.  These predicates are very
     * similar to an LDAP ASN.1 formatted query, except it has some additional information pertinent to opendirectoryd.
     *
     * The format of the predicate can either be a single predicate or a combination of nested predicates:
     *
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
     *
     * Predicate queries have a concept of a query start, result and finish.  When a query first starts the module should call:
     *
     *     odrequest_respond_query_start(request, context);
     *     odrequest_respond_query_result(request, context, result);
     *
     *     return odrequest_respond_success(request);
     */
    
#define USE_MODERN_PREDICATE_HANDLING 1
    
#if USE_MODERN_PREDICATE_HANDLING == 1
    NSArray<NSDictionary*> * standardPredicateList = CFBridgingRelease(xpctype_to_cftype(predicate));
    odrequest_log_message(request, eODLogInfo, CFSTR("Handling search request"));
    od_context_t context = odcontext_create(request, connection, NULL, ELReleaseOperationFromQueryContext);
    odrequest_respond_query_start(request, context);
    
    if (log_level_enabled(eODLogDebug)) {
        NSMutableArray<NSDictionary*> *humanReadablePredicateList = [NSMutableArray array];
        [standardPredicateList enumerateObjectsUsingBlock:^(NSDictionary * _Nonnull predicateDict, NSUInteger idx, BOOL * _Nonnull stop) {
            [humanReadablePredicateList addObject:[ELODToolbox humanReadableODPredicateDictionary:predicateDict]];
        }];
        
        odrequest_log_message(request, eODLogDebug, CFSTR("Handling search request with predicate:%@"), [ELODToolbox singleLineDescriptionForObject:humanReadablePredicateList]);
    }
    
    NSArray<NSDictionary*> *nativePredicateList = [ELODToolbox nativePredicatesEquivalence:standardPredicateList];
    
    [[ELAsyncBlockToManageAsOperation runOnSharedQueueOperationWithAsyncTask:^(ELAsyncBlockToManageAsOperation *currentOperation) {
        [[ELCachingDBProxy sharedInstance] getAllRegisteredRecordsMatchingPredicates:nativePredicateList
                                                               withCompletionHandler:^(NSArray<NSDictionary *> *results, NSError *error) {
                                                                   if (error) {
                                                                       odrequest_log_message(request, eODLogError, CFSTR("Unexpected error when handling predicates: %@"), error);
                                                                   } else {
                                                                       odrequest_log_message(request, eODLogInfo, CFSTR("Records found matching predicate criteria: %lu"), (unsigned long)[results count]);
                                                                       
                                                                       
                                                                       for (NSDictionary *record in results) {
                                                                           NSString *nativeRecordType = [record objectForKey:@"recordType"];
                                                                           
                                                                           odrequest_log_message(request, eODLogInfo, CFSTR("Full record loaded, sending back the answer"));
                                                                           NSDictionary *standardUserInfo = [[ELODToolbox sharedInstance] standardInfoFromNativeInfo:record ofType:nativeRecordType];
                                                                           
                                                                           if (log_level_enabled(eODLogDebug)) {
                                                                               odrequest_log_message(request, eODLogDebug, CFSTR("Record content is: %@"), [ELODToolbox singleLineDescriptionForObject:standardUserInfo]);
                                                                           }
                                                                           
                                                                           xpc_object_t resultDict = cftype_to_xpctype(standardUserInfo);
                                                                           odrequest_respond_query_result(request, context, resultDict);
                                                                           xpc_release(resultDict);
                                                                       }
                                                                   
                                                                   }
         
                                                                   [currentOperation considerThisOperationAsDone];
                                                               }];
    }
                                                      withCancelationHandler:nil
                                                                 andUserInfo:nil] waitUntilFinished];
    
    odrequest_respond_success(request);
    return eODCallbackResponseAccepted;
    
#else
    
    eODCallbackResponse response = eODCallbackResponseSkip;
    
    NSArray<NSDictionary*> * predicateList = CFBridgingRelease(xpctype_to_cftype(predicate));
    
    NSMutableArray<NSDictionary*> *humanReadablePredicateList = [NSMutableArray array];
    [predicateList enumerateObjectsUsingBlock:^(NSDictionary * _Nonnull predicateDict, NSUInteger idx, BOOL * _Nonnull stop) {
        [humanReadablePredicateList addObject:[ELODToolbox humanReadableODPredicateDictionary:predicateDict]];
    }];
    
    odrequest_log_message(request, eODLogInfo, CFSTR("Handling search request"));
    
    if (log_level_enabled(eODLogDebug)) {
        odrequest_log_message(request, eODLogDebug, CFSTR("Handling search request with predicate:%@"), [ELODToolbox singleLineDescriptionForObject:humanReadablePredicateList]);
        odrequest_log_message(request, eODLogDebug, CFSTR("Converted predicates:%@"), [ELODToolbox singleLineDescriptionForObject:[ELODToolbox nativePredicatesEquivalence:predicateList]]);
    }
    
    for (NSDictionary *predicatesInfo in predicateList) {
        
        if ([predicatesInfo objectForKey:[NSString stringWithUTF8String:kODKeyPredicateList]]) {
            odrequest_log_message(request, eODLogInfo, CFSTR("Recieved predicate is a complexe one (list of predicate with operator in between)"));
            
            //                NSString *operator = [predicatesInfo objectForKey:[NSString stringWithUTF8String:kODKeyPredicateOperator]];
            // Implementation needed with support for kODPredicateOperatorAnd kODPredicateOperatorOr and kODPredicateOperatorNot
            
            //                od_context_t context = odcontext_create(request, connection, NULL, ELReleaseOperationFromQueryContext);
            //                odrequest_respond_query_start(request, context);
            
            NSString *operator = [predicatesInfo objectForKey:[NSString stringWithUTF8String:kODKeyPredicateOperator]];
            
            if ([operator isEqualToString:[NSString stringWithUTF8String:kODPredicateOperatorOr]]) {
                
                od_context_t context = odcontext_create(request, connection, NULL, ELReleaseOperationFromQueryContext);
                odrequest_respond_query_start(request, context);
                odrequest_log_message(request, eODLogInfo, CFSTR("Initializing research for multiple predicates joined by OR operator"));
                
                NSString *nativeRecordType = [predicatesInfo objectForKey:[NSString stringWithUTF8String:kODKeyPredicateRecordType]];
                
                for (NSDictionary *subPredicate in [predicatesInfo objectForKey:[NSString stringWithUTF8String:kODKeyPredicateList]]) {
                    NSArray *lookedValues = [subPredicate objectForKey:[NSString stringWithUTF8String:kODKeyPredicateValueList]];
                    NSString *nativeAttribute = [subPredicate objectForKey:[NSString stringWithUTF8String:kODKeyPredicateAttribute]];
                    NSNumber *matchType = [subPredicate objectForKey:[NSString stringWithUTF8String:kODKeyPredicateMatchType]];
                    
                    switch ([matchType intValue]) {
                        case eODMatchTypeEqualTo: {
                            if ([lookedValues count] == 1) {
                                od_context_t context = odcontext_create(request, connection, NULL, ELReleaseOperationFromQueryContext);
                                odrequest_respond_query_start(request, context);
                                odrequest_log_message(request, eODLogInfo, CFSTR("Sub predicate is looking for a specific `%@.%@` value"), nativeRecordType, nativeAttribute);
                                
                                
                                [[ELAsyncBlockToManageAsOperation runOnSharedQueueOperationWithAsyncTask:^(ELAsyncBlockToManageAsOperation *currentOperation) {
                                    [[ELCachingDBProxy sharedInstance] getRegisteredRecordUUIDsOfType:nativeRecordType
                                                                                matchingAllAttributes:@{nativeAttribute: [lookedValues lastObject]}
                                                                                 andCompletionHandler:^(NSArray<NSString *> *results, NSError *error) {
                                                                                     if (error) {
                                                                                         odrequest_log_message(request, eODLogError, CFSTR("Unexpected error when handling sub predicate: %@"), error);
                                                                                     } else {
                                                                                         odrequest_log_message(request, eODLogInfo, CFSTR("Records found matching sub predicate criteria, loading full infos"));
                                                                                         
                                                                                         
                                                                                         for (NSString *userUUID in results) {
                                                                                             [[ELAsyncBlockToManageAsOperation runOnSharedQueueOperationWithAsyncTask:^(ELAsyncBlockToManageAsOperation *currentOperation) {
                                                                                                 [[ELCachingDBProxy sharedInstance] getRegisteredRecordOfType:nativeRecordType
                                                                                                                                                     withUUID:userUUID
                                                                                                                                         andCompletionHandler:^(NSDictionary *record, NSError *error) {
                                                                                                                                             if (error) {
                                                                                                                                                 odrequest_log_message(request, eODLogError, CFSTR("Unexpected error when loading full info for result record: %@"), error);
                                                                                                                                             } else {
                                                                                                                                                 odrequest_log_message(request, eODLogInfo, CFSTR("Full record loaded, sending back the answer"));
                                                                                                                                                 NSDictionary *standardUserInfo = [[ELODToolbox sharedInstance] standardInfoFromNativeInfo:record ofType:nativeRecordType];
                                                                                                                                                 
                                                                                                                                                 if (log_level_enabled(eODLogDebug)) {
                                                                                                                                                     odrequest_log_message(request, eODLogDebug, CFSTR("Record content is: %@"), [ELODToolbox singleLineDescriptionForObject:standardUserInfo]);
                                                                                                                                                 }
                                                                                                                                                 
                                                                                                                                                 xpc_object_t resultDict = cftype_to_xpctype(standardUserInfo);
                                                                                                                                                 odrequest_respond_query_result(request, context, resultDict);
                                                                                                                                                 xpc_release(resultDict);
                                                                                                                                             }
                                                                                                                                             [currentOperation considerThisOperationAsDone];
                                                                                                                                         }];
                                                                                                 
                                                                                             }
                                                                                                                                               withCancelationHandler:nil
                                                                                                                                                          andUserInfo:nil]waitUntilFinished];
                                                                                         }
                                                                                         
                                                                                     }
                                                                                     
                                                                                     [currentOperation considerThisOperationAsDone];
                                                                                 }];
                                    
                                }
                                                                                  withCancelationHandler:nil
                                                                                             andUserInfo:nil] waitUntilFinished];
                                
                            }
                            
                        } break;
                            
                        default:
                            break;
                    }
                }
                
                
                odrequest_respond_success(request);
                response = eODCallbackResponseAccepted;
            }
            
            
        } else {
            odrequest_log_message(request, eODLogInfo, CFSTR("Recieved predicate is a simple one (single predicate)"));
            
            NSNumber *matchType = [predicatesInfo objectForKey:[NSString stringWithUTF8String:kODKeyPredicateMatchType]];
            NSString *nativeRecordType = [predicatesInfo objectForKey:[NSString stringWithUTF8String:kODKeyPredicateRecordType]];
            
            
            if ([matchType intValue] == eODMatchTypeAll) {
                odrequest_log_message(request, eODLogInfo, CFSTR("Predicate just ask for all records of type `%@` without filterting crieria"), nativeRecordType);
                
                od_context_t context = odcontext_create(request, connection, NULL, ELReleaseOperationFromQueryContext);
                odrequest_respond_query_start(request, context);
                
                [[ELAsyncBlockToManageAsOperation runOnSharedQueueOperationWithAsyncTask:^(ELAsyncBlockToManageAsOperation *currentOperation) {
                    [[ELCachingDBProxy sharedInstance] getAllRegisteredRecordsOfType:nativeRecordType
                                                              withAttributesToReturn:@[
                                                                                       [[ELODToolbox sharedInstance] nativeAttrbuteForNativeType:nativeRecordType relatedToStandardAttribute:kODAttributeTypeRecordType],
                                                                                       [[ELODToolbox sharedInstance] nativeAttrbuteForNativeType:nativeRecordType relatedToStandardAttribute:kODAttributeTypeRecordName],
                                                                                       ]
                                                                andCompletionHandler:^(NSArray<NSDictionary *> *results, NSError *error) {
                                                                    if (error) {
                                                                        odrequest_log_message(request, eODLogError, CFSTR("Unexpected error when handling predicate: %@"), error);
                                                                    } else {
                                                                        odrequest_log_message(request, eODLogInfo, CFSTR("List of `%@` retrieved, sending informations"), nativeRecordType);
                                                                        for (NSDictionary *nativeUserInfo in results) {
                                                                            NSDictionary *standardUserInfo = [[ELODToolbox sharedInstance] standardInfoFromNativeInfo:nativeUserInfo ofType:nativeRecordType];
                                                                            
                                                                            if (log_level_enabled(eODLogDebug)) {
                                                                                odrequest_log_message(request, eODLogDebug, CFSTR("Record content sent is: %@"), [ELODToolbox singleLineDescriptionForObject:standardUserInfo]);
                                                                            }
                                                                            
                                                                            xpc_object_t resultDict = cftype_to_xpctype(standardUserInfo);
                                                                            odrequest_respond_query_result(request, context, resultDict);
                                                                            xpc_release(resultDict);
                                                                        }
                                                                    }
                                                                    [currentOperation considerThisOperationAsDone];
                                                                }];
                    
                    
                }
                                                                  withCancelationHandler:^(ELAsyncBlockToManageAsOperation *currentOperation) {
                                                                      
                                                                  }
                                                                             andUserInfo:nil] waitUntilFinished];
                
                odrequest_respond_success(request);
                response = eODCallbackResponseAccepted;
                
            } else {
                NSArray *rawLookedValues = [predicatesInfo objectForKey:[NSString stringWithUTF8String:kODKeyPredicateValueList]];
                NSMutableArray *lookedValues = [NSMutableArray new];
                NSString *standardAttribute = [predicatesInfo objectForKey:[NSString stringWithUTF8String:kODKeyPredicateStdAttribute]];
                NSString *nativeAttribute = [[ELODToolbox sharedInstance] nativeAttrbuteForNativeType:nativeRecordType relatedToStandardAttribute:standardAttribute];
                NSNumber *equalityType = [predicatesInfo objectForKey:[NSString stringWithUTF8String:kODKeyPredicateEquality]];
                
                if ([equalityType integerValue] == eODEqualityRuleNumber) {
                    NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
                    numberFormatter.numberStyle = NSNumberFormatterNoStyle;
                    
                    for (id value in rawLookedValues) {
                        if ([value isKindOfClass:[NSString class]]) {
                            NSNumber *realValue = [numberFormatter numberFromString:value];
                            if (realValue) {
                                [lookedValues addObject:realValue];
                            }
                        } else {
                            [lookedValues addObject:value];
                        }
                    }
                } else {
                    [lookedValues addObjectsFromArray:rawLookedValues];
                }
                
                
                switch ([matchType intValue]) {
                        //                    case eODMatchTypeContains: {
                        //                                for (NSString *targetValue in targetValues) {
                        //                                    if ([targetValue containsString:lookedValue]) {
                        //                                        xpc_object_t resultDict = cftype_to_xpctype(hardcordedUser);
                        //
                        //                                        odrequest_respond_query_result(request, context, resultDict);
                        //                                        xpc_release(resultDict);
                        //                                    }
                        //
                        //                                }
                        //                    } break;
                        
                    case eODMatchTypeEqualTo: {
                        odrequest_log_message(request, eODLogInfo, CFSTR("Predicate is looking for a specific `%@.%@` value"), nativeRecordType, nativeAttribute);
                        if ([lookedValues count] == 1) {
                            od_context_t context = odcontext_create(request, connection, NULL, ELReleaseOperationFromQueryContext);
                            odrequest_respond_query_start(request, context);
                            
                            [[ELAsyncBlockToManageAsOperation runOnSharedQueueOperationWithAsyncTask:^(ELAsyncBlockToManageAsOperation *currentOperation) {
                                [[ELCachingDBProxy sharedInstance] getRegisteredRecordUUIDsOfType:nativeRecordType
                                                                            matchingAllAttributes:@{nativeAttribute: [lookedValues lastObject]}
                                                                             andCompletionHandler:^(NSArray<NSString *> *results, NSError *error) {
                                                                                 if (error) {
                                                                                     odrequest_log_message(request, eODLogError, CFSTR("Unexpected error when handling predicate: %@"), error);
                                                                                 } else {
                                                                                     if ([results count] > 0) {
                                                                                         odrequest_log_message(request, eODLogInfo, CFSTR("Records found matching predicate criteria, loading full infos"));
                                                                                         
                                                                                         for (NSString *userUUID in results) {
                                                                                             [[ELAsyncBlockToManageAsOperation runOnSharedQueueOperationWithAsyncTask:^(ELAsyncBlockToManageAsOperation *currentOperation) {
                                                                                                 [[ELCachingDBProxy sharedInstance] getRegisteredRecordOfType:nativeRecordType
                                                                                                                                                     withUUID:userUUID
                                                                                                                                         andCompletionHandler:^(NSDictionary *record, NSError *error) {
                                                                                                                                             if (error) {
                                                                                                                                                 odrequest_log_message(request, eODLogError, CFSTR("Unexpected error when handling predicate: %@"), error);
                                                                                                                                             } else {
                                                                                                                                                 odrequest_log_message(request, eODLogInfo, CFSTR("Full record loaded, sending back the answer"));
                                                                                                                                                 
                                                                                                                                                 NSDictionary *standardUserInfo = [[ELODToolbox sharedInstance] standardInfoFromNativeInfo:record ofType:nativeRecordType];
                                                                                                                                                 
                                                                                                                                                 if (log_level_enabled(eODLogDebug)) {
                                                                                                                                                     odrequest_log_message(request, eODLogDebug, CFSTR("Record content is: %@"), [ELODToolbox singleLineDescriptionForObject:standardUserInfo]);
                                                                                                                                                 }
                                                                                                                                                 
                                                                                                                                                 xpc_object_t resultDict = cftype_to_xpctype(standardUserInfo);
                                                                                                                                                 odrequest_respond_query_result(request, context, resultDict);
                                                                                                                                                 xpc_release(resultDict);
                                                                                                                                             }
                                                                                                                                             [currentOperation considerThisOperationAsDone];
                                                                                                                                         }];
                                                                                                 
                                                                                             }
                                                                                                                                               withCancelationHandler:nil
                                                                                                                                                          andUserInfo:nil]waitUntilFinished];
                                                                                         }
                                                                                     } else {
                                                                                         odrequest_log_message(request, eODLogInfo, CFSTR("No records found matching predicate criteria"));
                                                                                     }
                                                                                 }
                                                                                 
                                                                                 [currentOperation considerThisOperationAsDone];
                                                                             }];
                                
                            }
                                                                              withCancelationHandler:nil
                                                                                         andUserInfo:nil] waitUntilFinished];
                            
                            
                            odrequest_log_message(request, eODLogInfo, CFSTR("Work done for predicate looking for a specific `%@.%@` value"), nativeRecordType, nativeAttribute);
                            odrequest_respond_success(request);
                            response = eODCallbackResponseAccepted;
                            
                        } else {
                            odrequest_log_message(request, eODLogError, CFSTR("Predicate is looking for multiple value associated to `%@.%@`, we don't know how to handle that!"), nativeRecordType, nativeAttribute);
                            odrequest_log_message(request, eODLogError, CFSTR("Predicate details need to be sent to EasyLogin support: %@"), humanReadablePredicateList);
                        }
                        
                    } break;
                        
                        //                    case eODMatchTypeBeginsWith: {
                        //                                for (NSString *targetValue in targetValues) {
                        //                                    if ([targetValue rangeOfString:lookedValue].location == 0) {
                        //                                        xpc_object_t resultDict = cftype_to_xpctype(hardcordedUser);
                        //
                        //                                        odrequest_respond_query_result(request, context, resultDict);
                        //                                        xpc_release(resultDict);
                        //                                    }
                        //                                }
                        
                        //                    } break;
                        
                        //                    case eODMatchTypeEndsWith: {
                        //                                for (NSString *targetValue in targetValues) {
                        //                                    if ([targetValue rangeOfString:lookedValue].location == [targetValue length] - [lookedValue length]) {
                        //                                        xpc_object_t resultDict = cftype_to_xpctype(hardcordedUser);
                        //
                        //                                        odrequest_respond_query_result(request, context, resultDict);
                        //                                        xpc_release(resultDict);
                        //                                    }
                        //                                }
                        
                        //                    } break;
                        
                    default: {
                        odrequest_log_message(request, eODLogError, CFSTR("Unknown predicate!"));
                        odrequest_log_message(request, eODLogError, CFSTR("Predicate details need to be sent to EasyLogin support: %@"), humanReadablePredicateList);
                    }
                        break;
                }
            }
        }
    }
    return response;
    
#endif
}

//static eODCallbackResponse ELQuerySynchronize(od_request_t request, od_connection_t connection, od_context_t query_context)
//{
//    /*! An Open Directory module odm_QuerySynchronize callback function.
//     *
//     *  The routine is called when a query is synchronised (via -[ODQuery synchronize]).
//     *  The goal is to reset the query so that it generates fresh results.
//     *
//     *  \param request The request that triggered the synchronise.
//     *  \param connection The connection that the query was run over.
//     *  \param queryContext The context associated with the query by ELQueryCreateWithPredicates.
//     *  \returns Typically eODCallbackResponseAccepted to indicate that the module accepted
//     *  the request, but other eODCallbackResponseXxx values are allowed.
//     */
//
//    odrequest_log_message(request, eODLogInfo, CFSTR("Synchronization request recieved, not supported at this time"));
//
//    return eODCallbackResponseSkip;
//}

//static eODCallbackResponse ELQueryCancel(od_request_t request, od_connection_t connection, od_context_t query_context)
//{
//    /*! An Open Directory module odm_QueryCancel callback function.
//     *
//     *  The routine is called when a query is cancelled.  The query should complete as soon
//     *  as possible.
//     *
//     *  \param request The request that triggered the synchronise.
//     *  \param connection The connection that the query was run over.
//     *  \param queryContext The context associated with the query by ELQueryCreateWithPredicates.
//     *  \returns Typically eODCallbackResponseAccepted to indicate that the module accepted
//     *  the request, but other eODCallbackResponseXxx values are allowed.
//     */
//
//    odrequest_log_message(request, eODLogInfo, CFSTR("Cancelation request recieved, not supported at this time"));
//
//    return eODCallbackResponseSkip;
//}

#pragma mark - Node Policy callbacks (a.k.a., global policies)

//static eODCallbackResponse ELNodeCopyPolicies(od_request_t request, od_connection_t connection)
//{
//    /* Responds to a request to fetch the node policy (i.e., global policy) */
//    odrequest_log_message(request, eODLogInfo, CFSTR("Node policy request recieved, not supported at this time"));
//    return eODCallbackResponseSkip;
//}

//static eODCallbackResponse ELNodeCopySupportedPolicies(od_request_t request, od_connection_t connection)
//{
//    /* responds with a dictionary of supported policies */
//
//    odrequest_log_message(request, eODLogInfo, CFSTR("Supported node policy request recieved, not supported at this time"));
//    return eODCallbackResponseSkip;
//}

#pragma mark -  Record Policy callbacks

/*
 * Open Directory has the concept of MetaRecordName, in other words, native record name.  All query results should contain
 * the key "dsAttrTypeStandard:AppleMetaRecordName" with an array of 1 value.
 *
 * That value is passed into every call (if present).  For example, LDAP module returns the record's native DN.
 */

//static eODCallbackResponse ELRecordCopyPolicies(od_request_t request, od_connection_t connection, const char *record_type, const char *metarecordname, const char *recordname, xpc_object_t addinfo_dict)
//{
//    odrequest_log_message(request, eODLogInfo, CFSTR("Record policy request recieved, not supported at this time"));
//    /* returns the current policy for this record */
//    return eODCallbackResponseSkip;
//}

//static eODCallbackResponse ELRecordCopyEffectivePolicies(od_request_t request, od_connection_t connection, const char *record_type, const char *metarecordname, const char *recordname, xpc_object_t addinfo_dict)
//{
//    odrequest_log_message(request, eODLogInfo, CFSTR("Record effective policy request recieved, not supported at this time"));
//    /* returns the effective policy for this record (combining the node policy with the record policy) */
//    return eODCallbackResponseSkip;
//}

//static eODCallbackResponse ELRecordCopySupportedPolicies(od_request_t request, od_connection_t connection, const char *record_type, const char *metarecordname, const char *recordname, xpc_object_t addinfo_dict)
//{
//
//    odrequest_log_message(request, eODLogInfo, CFSTR("Record supported policy request recieved, not supported at this time"));
//    /* returns the policies supported by this record */
//    return eODCallbackResponseSkip;
//}


#pragma mark - Password expiration and locked account

//static eODCallbackResponse ELRecordAuthenticationAllowed(od_request_t request, od_connection_t connection, const char *record_type, const char *metarecordname, const char *recordname, xpc_object_t addinfo_dict)
//{
//    odrequest_log_message(request, eODLogInfo, CFSTR("Checking if record has right to get authenticated"));
//
//    return eODCallbackResponseAccepted;
//}
//
//static eODCallbackResponse ELRecordPasswordChangeAllowed(od_request_t request, od_connection_t connection, const char *record_type, const char *metarecordname, const char *recordname, const char *password, xpc_object_t addinfo_dict)
//{
//    odrequest_log_message(request, eODLogInfo, CFSTR("Checking if record has right to change its password"));
//    return eODCallbackResponseSkip;
//}
//
//static eODCallbackResponse ELRecordWillPasswordExpire(od_request_t request, od_connection_t connection, const char *record_type, const char *metarecordname, const char *recordname, int64_t expires_in, xpc_object_t addinfo_dict)
//{
//    odrequest_log_message(request, eODLogInfo, CFSTR("Checking if record's password will expire"));
//    return eODCallbackResponseSkip;
//}
//
//static eODCallbackResponse ELRecordSecondsUntilPasswordExpires(od_request_t request, od_connection_t connection, const char *record_type, const char *metarecordname, const char *recordname, xpc_object_t addinfo_dict)
//{
//    odrequest_log_message(request, eODLogInfo, CFSTR("Sending time in second before password expiration"));
//    return eODCallbackResponseSkip;
//}

#pragma mark - Node authentication / used by dscl for test login

//static eODCallbackResponse ELNodeSetCredentials(od_request_t request, od_connection_t connection, const char *record_type, const char *metarecordname, const char *recordname, const char *password, xpc_object_t addinfo_dict)
//{
//    /*
//     * This is called when a client is attaching credentials to a given connection.   If no additional work is required for this
//     * operation, then it can just be responded to with no error.  If no error is returned, then an appropriate od_credential_t
//     * will be attached to the connection.
//     *
//     *     return odrequest_respond_success(request);
//     *
//     * If additional work is required, then that work can eiher be handled directly or done asynchronously.  The module
//     * must return eODCallbackResponseAccepted if it is to be handled, or use the return from the odrequest_respond* APIs.
//     */
//    odrequest_log_message(request, eODLogInfo, CFSTR("Credential set for node. Not supported at this time"));
//
//    return eODCallbackResponseSkip;
//}

#pragma mark - entry

int main(int argc, const char *argv[])
{
    static struct odmodule_vtable_s vtable = {
        .version = ODMODULE_VTABLE_VERSION,
        
        .odm_initialize = ELModuleInit,
        .odm_configuration_loaded = ELConfigLoaded,
        .odm_create_connection_with_options = ELCreateConnectionWithOptions,
        //        .odm_parse_dynamic_destination = ELParseDynamicDestination,
        .odm_copy_details = ELCopyDetails,
        
        //        .odm_NodeCopyPolicies = ELNodeCopyPolicies,
        //        .odm_NodeCopySupportedPolicies = ELNodeCopySupportedPolicies,
        
        .odm_QueryCreateWithPredicates = ELQueryCreateWithPredicates,
        //        .odm_QuerySynchronize = ELQuerySynchronize,
        //        .odm_QueryCancel = ELQueryCancel,
        
        //        .odm_RecordCopyPolicies = ELRecordCopyPolicies,
        //        .odm_RecordCopyEffectivePolicies = ELRecordCopyEffectivePolicies,
        //        .odm_RecordCopySupportedPolicies = ELRecordCopySupportedPolicies,
        
        .odm_copy_auth_information = ELCopyAuthInfo,
        .odm_RecordVerifyPassword = ELRecordVerifyPassword,
        //        .odm_RecordVerifyPasswordExtended = ELRecordVerifyPasswordExtended,
        .odm_RecordChangePassword = ELRecordChangePassword,
        
        //        .odm_RecordAuthenticationAllowed = ELRecordAuthenticationAllowed,
        //        .odm_RecordPasswordChangeAllowed = ELRecordPasswordChangeAllowed,
        //        .odm_RecordWillPasswordExpire = ELRecordWillPasswordExpire,
        //        .odm_RecordSecondsUntilPasswordExpires = ELRecordSecondsUntilPasswordExpires,
        
        //        .odm_NodeSetCredentials = ELNodeSetCredentials,
        
    };
    
    odmodule_main(&vtable);
    
    // odmodule_main is not supposed to return, so if it does we return with
    // EXIT_FAILURE.
    
    return EXIT_FAILURE;
}
