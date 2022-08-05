//
//  PhotoGroupApp.swift
//  Shared
//
//  Created by Lawrence D'Anna on 3/4/22.
//

import SwiftUI
import Photos
import CryptoKit
import SwiftCSV

func csvQuote(_ s:String) -> String {
    if s.rangeOfCharacter(from: CharacterSet(charactersIn: ",\"\r\n")) != nil {
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    } else {
        return s
    }
}

func hexDigest<T: HashFunction>(hash: T) -> String {
    return String(hash.finalize().flatMap { byte in
        String(format:"%02x", byte)
    })
}

func w_rename(old: String, new :String) throws -> ()  {
    let r = rename(NSString(string: old).utf8String, NSString(string: new).utf8String)
    if r < 0 {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}

let dateStyle = Date.ISO8601FormatStyle(dateSeparator: .dash , dateTimeSeparator: .space, timeZone: .current)

struct RuntimeError: Error {
    var message : String
    
}


@main
struct PhotoGroupApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
    
    func documentPath(filename: String) throws -> String {
        let documentsDirectories = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        if documentsDirectories.count < 1 {
            throw RuntimeError(message: "can't find Documents folder")
        }
        let documentsDirectory = documentsDirectories[0]
        return documentsDirectory.appendingPathComponent(filename).path
    }
    
    func readCSV(path: String) throws {
        
        print("reading csv from", path)

        if !FileManager.default.fileExists(atPath: path) {
            return
        }
        
        let data = try String(contentsOf: URL.init(fileURLWithPath: path))
        
        print("len data = ", data.count)
        
        let csv = try NamedCSV(string: data)
        
        for row in csv.rows {
            print("row", row)
            let d = try Date(row["modificationDate"]!, strategy: dateStyle)
            print(d)

        }
    }
    
    func writeCSV(path:String) throws {
        
        let tmp_path = path + ".tmp"
        print("writing csv to ", tmp_path)
        FileManager.default.createFile(atPath: tmp_path, contents: Data(), attributes: nil)
        guard let f = FileHandle(forWritingAtPath: tmp_path) else {
            throw RuntimeError(message: "can't open csv file for writing")
        }

        f.write("id,creationDate,modificationDate,mediaType,mediaSubtypes,flags,resourceType,filename,size,sha256,url\n".data(using: .utf8)!)

        let fetchResult = Photos.PHAsset.fetchAssets(with: PHFetchOptions())

        let g = DispatchGroup()
        
        for i in 0..<fetchResult.count {
            let asset : PHAsset = fetchResult.object(at: i)
            //print("LOL", asset, asset.localIdentifier)
            
            if asset.mediaType != .image {
                continue
            }
            
            for resource in PHAssetResource.assetResources(for: asset) {
                g.enter()
                var count = 0
                var hash = SHA256()
                PHAssetResourceManager.default().requestData(for: resource, options: nil) { data in
                    count += data.count
                    hash.update(data: data)
                } completionHandler: { e in
                    let flags = asset.isFavorite ? "❤️" : ""
                    let line = String(format: "%@,%@,%@,%d,%d,%@,%d,%@,%d,%@,%@",
                                      asset.localIdentifier,
                                      asset.creationDate?.ISO8601Format(dateStyle) ?? "",
                                      asset.modificationDate?.ISO8601Format(dateStyle) ?? "",
                                      asset.mediaType.rawValue,
                                      asset.mediaSubtypes.rawValue,
                                      flags,
                                      resource.type.rawValue,
                                      csvQuote(resource.originalFilename),
                                      count,
                                      e == nil ?  hexDigest(hash: hash) : "",
                                      csvQuote(resource_fileURL(resource)?.absoluteString ?? ""))

                    f.write(line.data(using: .utf8)!)
                    f.write("\n".data(using: .utf8)!)
                    print(line)
                    g.leave()
                }
            }
            
            if i > 10 {
                break
            }
        }

        g.wait()
        
        try f.close()
        print("moving to ", path)
        try w_rename(old: tmp_path, new: path)
        
        print("done writing csv")
        

    }

    func gotAuthorization(_ status:PHAuthorizationStatus) {
        if status != .authorized {
            print("==not authorized :(")
            return
        }
        print ("==got authorization.")
        do {
            let assets_csv_path = try documentPath(filename: "assets.csv")
            try self.readCSV(path: assets_csv_path)
            try self.writeCSV(path: assets_csv_path)
        } catch {
            print("oh no!")
        }
    }
    
    init() {
        print("==requesting authorization.....")
        Photos.PHPhotoLibrary.requestAuthorization(for: .readWrite, handler:self.gotAuthorization)
        
    }
}
