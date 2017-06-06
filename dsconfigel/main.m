//
//  main.m
//  ELConfigTool
//
//  Created by Yoann Gini on 26/05/2017.
//  Copyright © 2017 EasyLogin. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Configuration.h"

#import <OpenDirectory/OpenDirectory.h>


int main(int argc, const char * argv[]) {
    int exitCode = EXIT_FAILURE;
    @autoreleasepool {        
        Configuration *config = [Configuration new];
        exitCode = [config run];
    }
    return exitCode;
}
