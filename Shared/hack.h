//
//  hack.h
//  PhotoGroup
//
//  Created by Lawrence D'Anna on 8/4/22.
//

#ifndef hack_h
#define hack_h

#import <Foundation/Foundation.h>
#import <Photos/Photos.h>

NSURL *resource_fileURL(PHAssetResource *resource);
long long resource_fileSize(PHAssetResource *resource);


#endif /* hack_h */
