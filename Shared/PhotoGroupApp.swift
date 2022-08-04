//
//  PhotoGroupApp.swift
//  Shared
//
//  Created by Lawrence D'Anna on 3/4/22.
//

import SwiftUI
import Photos

@main
struct PhotoGroupApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
    
    func gotAuthorization(_ status:PHAuthorizationStatus) {
        if status != .authorized {
            print("not authorized :(")
            return
        }
        print ("!!!===!!!  got auth!")
        let fetchResult = Photos.PHAsset.fetchAssets(with: PHFetchOptions())
        print("========lol!!!", fetchResult.count)
        
        for i in 0..<fetchResult.count {
            let asset : PHAsset = fetchResult.object(at: i)
            print("LOL", asset, asset.localIdentifier)
            
            if asset.mediaType != .image {
                continue
            }
            

            let opts = PHContentEditingInputRequestOptions()
            asset.requestContentEditingInput(with: opts) { input, info in
                guard let input = input else {
                    print("=======input is nil! ");
                    return;
                }
                guard let url = input.fullSizeImageURL else {
                    print("======= no url")
                    return
                }
                print("=========!!!!=======got input!", input, info, url)
            }


        }
    }
    
    init() {
        print("======== requesting authorization.....")
        Photos.PHPhotoLibrary.requestAuthorization(for: .readWrite, handler:self.gotAuthorization)
        
    }
}
