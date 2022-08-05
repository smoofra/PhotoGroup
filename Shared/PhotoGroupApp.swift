//
//  PhotoGroupApp.swift
//  Shared
//
//  Created by Lawrence D'Anna on 3/4/22.
//

import SwiftUI
import Photos

func quote(_ s:String) -> String {
    if s.rangeOfCharacter(from: CharacterSet(charactersIn: ",\"\r\n")) != nil {
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    } else {
        return s
    }
}

let style = Date.ISO8601FormatStyle(dateSeparator: .dash , dateTimeSeparator: .space, timeZone: .current)

@main
struct PhotoGroupApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
    
    func writeCSV(filename:String) {

        let documentsDirectories = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        if documentsDirectories.count < 1 {
            print("can't find Documents")
        }
        let documentsDirectory = documentsDirectories[0]
        let path = documentsDirectory.appendingPathComponent(filename).path
        print("writing csv to ", path)
        FileManager.default.createFile(atPath: path, contents: Data(), attributes: nil)
        guard let f = FileHandle(forWritingAtPath: path) else {
            print("can't open file:", path);
            return;
        }

        f.write("id,creationDate,modificationDate,mediaType,mediaSubtypes,flags,resourceType,filename,size,url\n".data(using: .utf8)!)

        let fetchResult = Photos.PHAsset.fetchAssets(with: PHFetchOptions())

        let g = DispatchGroup()
        
        for i in 0..<fetchResult.count {
            let asset : PHAsset = fetchResult.object(at: i)
            //print("LOL", asset, asset.localIdentifier)
            
            if asset.mediaType != .image {
                continue
            }
            
            
            for resource in PHAssetResource.assetResources(for: asset) {
                
                let flags = asset.isFavorite ? "❤️" : ""
                
                let line = String(format: "%@,%@,%@,%d,%d,%@,%d,%@,%d,%@\n",
                                  asset.localIdentifier,
                                  asset.creationDate?.ISO8601Format(style) ?? "",
                                  asset.modificationDate?.ISO8601Format(style) ?? "",
                                  asset.mediaType.rawValue,
                                  asset.mediaSubtypes.rawValue,
                                  flags,
                                  resource.type.rawValue,
                                  quote(resource.originalFilename),
                                  resource_fileSize(resource),
                                  quote(resource_fileURL(resource)?.absoluteString ?? ""))


                f.write(line.data(using: .utf8)!)

            }
        }



        g.wait()
        print("done")
    }

    func gotAuthorization(_ status:PHAuthorizationStatus) {
        if status != .authorized {
            print("==not authorized :(")
            return
        }
        print ("==got authorization.")
        self.writeCSV(filename: "assets.csv")
    }
    
    init() {
        print("==requesting authorization.....")
        Photos.PHPhotoLibrary.requestAuthorization(for: .readWrite, handler:self.gotAuthorization)
        
    }
}
