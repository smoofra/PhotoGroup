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

@main
struct PhotoGroupApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
    
    func writeCSV(path:String) {

        FileManager.default.createFile(atPath: path,  contents:Data(), attributes: nil)
        guard let f = FileHandle(forWritingAtPath: path) else {
            print("can't open file");
            return;
        }

        f.write("creationDate,modificationDate,mediaType,mediaSubtypes,flags,url\n".data(using: .utf8)!)

        let fetchResult = Photos.PHAsset.fetchAssets(with: PHFetchOptions())

        let g = DispatchGroup()
        
        for i in 0..<fetchResult.count {
            let asset : PHAsset = fetchResult.object(at: i)
            //print("LOL", asset, asset.localIdentifier)
            
            if asset.mediaType != .image {
                continue
            }
            
            let resources = PHAssetResource.assetResources(for: asset)
            if resources.count > 1 {
                print("oh oh", resources);
            }

            
            

            let opts = PHContentEditingInputRequestOptions()
            g.enter()
            asset.requestContentEditingInput(with: opts) { input, info in
                defer { g.leave() }
                guard let input = input else {
                    print("==input is nil! ");
                    return;
                }

                let style = Date.ISO8601FormatStyle(dateSeparator: .dash , dateTimeSeparator: .space, timeZone: .current)

                var flags = ""
                if input.adjustmentData != nil {
                    flags += "🎛️"
                }
                if asset.isFavorite {
                    flags += "❤️"
                }


                let line = String(format: "%@,%@,%d,%d,%@,%@\n",
                                  asset.creationDate?.ISO8601Format(style) ?? "",
                                  asset.modificationDate?.ISO8601Format(style) ?? "",
                                  asset.mediaType.rawValue,
                                  asset.mediaSubtypes.rawValue,
                                  flags,
                                  quote(input.fullSizeImageURL?.absoluteString ?? ""))
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
        self.writeCSV(path: "/tmp/assets.csv")
    }
    
    init() {
        print("==requesting authorization.....")
        Photos.PHPhotoLibrary.requestAuthorization(for: .readWrite, handler:self.gotAuthorization)
        
    }
}
