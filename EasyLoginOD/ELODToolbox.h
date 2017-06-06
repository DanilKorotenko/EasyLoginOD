//
//  ELODToolbox.h
//  EasyLoginOD
//
//  Created by Yoann Gini on 05/06/2017.
//  Copyright © 2017 Yoann Gini (Open Source Project). All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ELODToolbox : NSObject

+ (instancetype)sharedInstance;

- (NSDictionary*)standardInfoFromNativeInfo:(NSDictionary*)nativeInfo ofType:(NSString *)nativeType;

@end
