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

extension UInt8 {
    var hexDigitValue : Int? {
        get {
            return Character(UnicodeScalar(self)).hexDigitValue
            
        }
    }
}
extension Digest {
    
    func toHex() -> String {
        return String(self.flatMap { byte in
            String(format:"%02x", byte)
        })
    }
    
    static func fromHex(_ string : String) -> Self? {
        let utf8 = string.utf8
        let data = UnsafeMutableRawBufferPointer.allocate(byteCount: Self.byteCount, alignment: 8)
        defer { data.deallocate() }
        if utf8.count != 2 * Self.byteCount { return nil }
        for i in stride(from: 0, to: 2*Self.byteCount, by: 2) {
            guard
               let high = utf8[utf8.index(utf8.startIndex, offsetBy: i)].hexDigitValue,
               let low = utf8[utf8.index(utf8.startIndex, offsetBy: i+1)].hexDigitValue
            else { return nil }
            data[i/2] = UInt8(high * 16 + low)
        }
        return data.bindMemory(to: Self.self)[0]
    }
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

func unwrap<T> (_ o : T?) throws -> T {
    if let v = o {
        return v
    } else {
        throw RuntimeError(message: "bad/missing value")
    }
}

func resource_path(resource : PHAssetResource) -> String? {
    guard let url = resource_fileURL(resource) else {
        return nil
    }
    if !url.isFileURL {
        return nil
    }
    return url.path
}

func parseInt(_ s : String) throws -> Int {
    if let i = Int(s) {
        return i
    } else {
        throw RuntimeError(message: "invalid data")
    }
}

func parseUInt(_ s : String) throws -> UInt {
    if let i = UInt(s) {
        return i
    } else {
        throw RuntimeError(message: "invalid data")
    }
}


struct Resource {
    var url : String?
    var size : UInt64?
    var hash : SHA256Digest?
    var type : PHAssetResourceType
    var filename: String
    var uti : String
}

struct Asset {
    var id : String
    var creationDate: Date?
    var modificationDate: Date?
    var mediaType: PHAssetMediaType
    var mediaSubtypes: PHAssetMediaSubtype
    var isFavorite: Bool
    var resources: [Resource]
}

struct LimitQueue {
    var sem : DispatchSemaphore
    var q : DispatchQueue
    
    init(limit : Int, qos : DispatchQoS, label: String) {
        self.sem = DispatchSemaphore(value: limit)
        self.q = DispatchQueue(label: label, qos: qos, attributes: DispatchQueue.Attributes(), autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency .inherit, target: nil)
    }
    
    public func async(group: DispatchGroup? = nil, qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [], execute work: @escaping @convention(block) () -> Void) {
        self.q.async {
            self.sem.wait()
            DispatchQueue.global().async(group: group, qos: qos, flags: flags) {
                work()
                self.sem.signal()
            }
        }
    }
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
    
    func readCSV(path: String) throws -> [String: Asset] {
        
        var assets = [String:Asset]()
        
        print("reading csv from", path)

        if !FileManager.default.fileExists(atPath: path) {
            return assets
        }
        
        let data = try String(contentsOf: URL.init(fileURLWithPath: path))
        let csv = try NamedCSV(string: data, loadColumns: false)
            
        for k in ["modificationDate"] {
            if !csv.header.contains(k) {
                throw RuntimeError(message: "csv is incomplete")
            }
        }
        
        var asset_id : String?
        var asset: Asset?
        for row in csv.rows {
            do {
                let id = try unwrap(row["id"])
                if id != asset_id {
                    asset_id = id
                    asset = Asset(
                        id: id,
                        creationDate: try Date(try unwrap(row["creationDate"]), strategy: dateStyle),
                        modificationDate: try Date(try unwrap(row["modificationDate"]), strategy: dateStyle),
                        mediaType:  try unwrap(PHAssetMediaType(rawValue: try parseInt(try unwrap(row["mediaType"])))),
                        mediaSubtypes: PHAssetMediaSubtype(rawValue:  try parseUInt(try unwrap(row["mediaSubtypes"]))),
                        isFavorite: try unwrap(row["flags"]).contains("❤️"),
                        resources: [Resource]())
                    assets[id] = asset
                }
                
                assets[id]!.resources.append(Resource(
                    url: try unwrap(row["url"]),
                    size: UInt64(try unwrap(row["size"])),
                    hash: SHA256Digest.fromHex(try unwrap(row["sha256"])),
                    type: try unwrap(PHAssetResourceType(rawValue: try parseInt(try unwrap(row["resourceType"])))),
                    filename: try unwrap(row["filename"]),
                    uti: try unwrap(row["uti"])))
            } catch {
                print("bad row: ", row)
            }
        }
        
        return assets
    }
    
    func update(asset : inout Asset?, phasset : PHAsset) {
        
        let complete = asset?.resources.allSatisfy({ resource in resource.hash != nil && resource.size != nil }) ?? false

        if complete,
           let asset = asset,
           let asset_date = asset.modificationDate,
           let phasset_date = phasset.modificationDate,
           asset_date <= phasset_date
        {
            print("asset", phasset.localIdentifier, "is up to date")
            return
        }
        
        let phresources = PHAssetResource.assetResources(for: phasset)

        var resources = Array<Resource?>(repeating: nil, count: phresources.count)
        
        let g = DispatchGroup()
        for (i, phresource) in phresources.enumerated()  {
            g.enter()
            var count : UInt64 = 0
            var hash = SHA256()
            print("hashing ", phasset.localIdentifier, phresource.originalFilename)
            PHAssetResourceManager.default().requestData(for: phresource, options: nil) { data in
                count += UInt64(data.count)
                hash.update(data: data)
            } completionHandler: { e in
                defer { g.leave() }
                var digest : SHA256Digest? = nil
                var size : UInt64? = nil
                if e != nil {
                    print("hashing failed", e as Any)
                } else {
                    digest = hash.finalize()
                    size = count
                }
                resources[i] = Resource(
                    url: resource_fileURL(phresource)?.absoluteString,
                    size : size,
                    hash: digest,
                    type: phresource.type,
                    filename: phresource.originalFilename,
                    uti: phresource.uniformTypeIdentifier)
            }
        }
        g.wait()
        
        asset = Asset(id: phasset.localIdentifier,
                      creationDate: phasset.creationDate,
                      modificationDate: phasset.modificationDate,
                      mediaType: phasset.mediaType,
                      mediaSubtypes: phasset.mediaSubtypes,
                      isFavorite: phasset.isFavorite,
                      resources: resources.map({r in r!}))

    }
    
    func update(assets : inout [String:Asset]) throws {
        
        let fetchResult = Photos.PHAsset.fetchAssets(with: PHFetchOptions())

        let q = LimitQueue(limit: 8, qos: .userInitiated, label: "update")
        let g = DispatchGroup()
        for i in 0..<fetchResult.count {
            let phasset : PHAsset = fetchResult.object(at: i)
            let id = phasset.localIdentifier
            var asset = assets[id]
            g.enter()
            q.async(group: g, qos: .unspecified, flags: []) {
                self.update(asset: &asset, phasset: phasset)
                assets[id] = asset
                g.leave()
            }
        }
        g.wait()
        
        print("all done")
        
    }
    
    
    func writeCSV(assets: [String:Asset], path:String) throws {
        
        let tmp_path = path + ".tmp"
        print("writing csv to ", tmp_path)
        FileManager.default.createFile(atPath: tmp_path, contents: Data(), attributes: nil)
        guard let f = FileHandle(forWritingAtPath: tmp_path) else {
            throw RuntimeError(message: "can't open csv file for writing")
        }

        f.write("id,creationDate,modificationDate,mediaType,mediaSubtypes,flags,resourceType,uti,filename,size,sha256,url\n".data(using: .utf8)!)
        
        for (_, asset) in assets {
            for resource in asset.resources {
                
                let flags = asset.isFavorite ? "❤️" : ""
                let fields = [
                      asset.id,
                      asset.creationDate?.ISO8601Format(dateStyle) ?? "",
                      asset.modificationDate?.ISO8601Format(dateStyle) ?? "",
                      String(asset.mediaType.rawValue),
                      String(asset.mediaSubtypes.rawValue),
                      flags,
                      String(resource.type.rawValue),
                      resource.uti,
                      csvQuote(resource.filename),
                      resource.size != nil ? String(resource.size!) : "",
                      resource.hash?.toHex() ?? "",
                      resource.url ?? "",
                ]
                let line = fields.joined(separator: ",")
                f.write(line.data(using: .utf8)!)
                f.write("\n".data(using: .utf8)!)
                //print(line)
            }
        }
        
        try f.close()
        print("moving to ", path)
        try w_rename(old: tmp_path, new: path)
        print("done writing csv")
    }

    
    func writeCSV0(path:String) throws {
        
        let tmp_path = path + ".tmp"
        print("writing csv to ", tmp_path)
        FileManager.default.createFile(atPath: tmp_path, contents: Data(), attributes: nil)
        guard let f = FileHandle(forWritingAtPath: tmp_path) else {
            throw RuntimeError(message: "can't open csv file for writing")
        }

        f.write("id,creationDate,modificationDate,mediaType,mediaSubtypes,flags,resourceType,uti,filename,size,sha256,url\n".data(using: .utf8)!)

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
                    let fields = [
                          asset.localIdentifier,
                          asset.creationDate?.ISO8601Format(dateStyle) ?? "",
                          asset.modificationDate?.ISO8601Format(dateStyle) ?? "",
                          String(asset.mediaType.rawValue),
                          String(asset.mediaSubtypes.rawValue),
                          flags,
                          String(resource.type.rawValue),
                          resource.uniformTypeIdentifier,
                          csvQuote(resource.originalFilename),
                          String(count),
                          e == nil ?  hexDigest(hash: hash) : "",
                          csvQuote(resource_fileURL(resource)?.absoluteString ?? "")
                    ]
                    let line = fields.joined(separator: ",")

                    f.write(line.data(using: .utf8)!)
                    f.write("\n".data(using: .utf8)!)
                    print(line)
                    g.leave()
                }
            }
            
            if i > 20 {
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
            var assets = try self.readCSV(path: assets_csv_path)
            try self.update(assets: &assets)
            try self.writeCSV(assets: assets, path: assets_csv_path)
        } catch let e as RuntimeError {
            print("oh noe", e)
        } catch let e {
            print("oh no!", e)
        }
    }
    
    init() {
        print("==requesting authorization.....")
        Photos.PHPhotoLibrary.requestAuthorization(for: .readWrite, handler:self.gotAuthorization)
        
    }
}
