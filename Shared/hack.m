//
//  hack.m
//  PhotoGroup
//
//  Created by Lawrence D'Anna on 8/4/22.
//

#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>

#include "hack.h"

NSURL *resource_fileURL(PHAssetResource *resource) {
    Ivar var = class_getInstanceVariable([resource class], "_privateFileURL");
    if (var == nil) {
        return nil;
    }
    id value = object_getIvar(resource, var);
    if ([value isKindOfClass:[NSURL class]]) {
        return value;
    } else {
        return nil;
    }

}

long long resource_fileSize(PHAssetResource *resource) {
    Ivar var = class_getInstanceVariable([resource class], "_fileSize");
    if (var == nil) {
        return -1;
    }
    return (uintptr_t)(__bridge void*) object_getIvar(resource, var);
}
