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
import os


func csvQuote(_ s:String) -> String {
    if s.rangeOfCharacter(from: CharacterSet(charactersIn: ",\"\r\n")) != nil {
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    } else {
        return s
    }
}

extension Digest {
    
    func toHex() -> String {
        return String(self.flatMap { byte in
            String(format:"%02x", byte)
        })
    }
    
    static func fromHex(_ string : String) -> Self? {
        let data = UnsafeMutableRawBufferPointer.allocate(byteCount: Self.byteCount, alignment: 8)
        defer { data.deallocate() }
        let utf8 = string.utf8
        if utf8.count != 2 * Self.byteCount { return nil }
        func digit(_ i : Int) -> Int? {
            let byte = utf8[utf8.index(utf8.startIndex, offsetBy: i)]
            return Character(UnicodeScalar(byte)).hexDigitValue
        }
        for i in stride(from: 0, to: 2*Self.byteCount, by: 2) {
            guard
                let high = digit(i),
                let low = digit(i+1)
            else { return nil }
            data[i/2] = UInt8(high * 16 + low)
        }
        return data.bindMemory(to: Self.self)[0]
    }
}

extension PHAssetResource {
    var path : String? {
        get {
            guard let url = resource_fileURL(self)
            else { return nil}
            if !url.isFileURL {
                return nil
            }
            return url.path
        }
    }
}

extension PHCloudIdentifier {
    static func maybe(_ s: String?) -> PHCloudIdentifier? {
        if let s = s {
            if s != "" {
                return PHCloudIdentifier(stringValue: s)
            }
        }
        return nil
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
    var path : String?
    var size : UInt64?
    var hash : SHA256Digest?
    var type : PHAssetResourceType
    var filename: String
    var uti : String
}

struct Asset {
    var id : String
    var cloudid : PHCloudIdentifier?
    var creationDate: Date?
    var modificationDate: Date?
    var mediaType: PHAssetMediaType
    var mediaSubtypes: PHAssetMediaSubtype
    var isFavorite: Bool
    var resources: [Resource]
}

struct Album {
    var title : String?
    var assetIds: Set<String>
}

func csvSplit(s : String) throws -> [String] {
    let csv = try EnumeratedCSV(string: "\n" + s, loadColumns: false)
    if csv.rows.count == 0 {
        return []
    }
    if csv.rows.count != 1 {
        throw RuntimeError(message: "parse error")
    }
    return csv.rows[0]
}

func readAssetsCSV(path: String) throws -> [String: Asset] {
    
    var assets = [String:Asset]()
    
    print("reading csv from", path)

    if !FileManager.default.fileExists(atPath: path) {
        return assets
    }
    
    let data = try String(contentsOf: URL.init(fileURLWithPath: path))
    let csv = try NamedCSV(string: data, loadColumns: false)
    
    var asset_id : String?
    var asset: Asset?
    for row in csv.rows {
        
        let id = try unwrap(row["id"])
        if id != asset_id {
            let _ = try csvSplit(s: try unwrap(row["albums"]))
            let _ = try csvSplit(s: try unwrap(row["albumIds"]))
            
            asset_id = id
            asset = Asset(
                id: id,
                cloudid: PHCloudIdentifier.maybe(row["cloudId"]),
                creationDate: try Date(try unwrap(row["creationDate"]), strategy: dateStyle),
                modificationDate: try Date(try unwrap(row["modificationDate"]), strategy: dateStyle),
                mediaType:  try unwrap(PHAssetMediaType(rawValue: try parseInt(try unwrap(row["mediaType"])))),
                mediaSubtypes: PHAssetMediaSubtype(rawValue:  try parseUInt(try unwrap(row["mediaSubtypes"]))),
                isFavorite: try unwrap(row["flags"]).contains("❤️"),
                resources: [Resource]())

            assets[id] = asset
        }
        
        assets[id]!.resources.append(Resource(
            path: row["path"],
            size: UInt64(try unwrap(row["size"])),
            hash: SHA256Digest.fromHex(try unwrap(row["sha256"])),
            type: try unwrap(PHAssetResourceType(rawValue: try parseInt(try unwrap(row["resourceType"])))),
            filename: try unwrap(row["filename"]),
            uti: try unwrap(row["uti"])))
        
    }
    
    return assets
}


func writeAssetsCSV(assets: [String:Asset], albums: [String:Album], path:String) throws {
    
    let tmp_path = path + ".tmp"
    print("writing csv to ", tmp_path)
    FileManager.default.createFile(atPath: tmp_path, contents: Data(), attributes: nil)
    guard let f = FileHandle(forWritingAtPath: tmp_path) else {
        throw RuntimeError(message: "can't open csv file for writing")
    }

    f.write("id,cloudId,creationDate,modificationDate,mediaType,mediaSubtypes,flags,resourceType,uti,filename,size,sha256,albums,albumIds,path\n".data(using: .utf8)!)
    
    for (_, asset) in assets {
        
        let albums : [(String,String?)] = albums.compactMap { (key: String, album: Album) in
            if album.assetIds.contains(asset.id) {
                return (key, album.title)
            } else {
                return nil
            }
        }

        let albumIds = albums.map { (id,name) in csvQuote(id) }.joined(separator: " ")
        let albumsNames = albums.compactMap { (id,name) in name }.map(csvQuote).joined(separator: "; ")
        let flags = asset.isFavorite ? "❤️" : ""
        
        for resource in asset.resources {

            let fields = [
                  csvQuote(asset.id),
                  csvQuote(asset.cloudid?.stringValue ?? ""),
                  asset.creationDate?.ISO8601Format(dateStyle) ?? "",
                  asset.modificationDate?.ISO8601Format(dateStyle) ?? "",
                  String(asset.mediaType.rawValue),
                  String(asset.mediaSubtypes.rawValue),
                  flags,
                  String(resource.type.rawValue),
                  csvQuote(resource.uti),
                  csvQuote(resource.filename),
                  resource.size != nil ? String(resource.size!) : "",
                  resource.hash?.toHex() ?? "",
                  csvQuote(albumsNames),
                  csvQuote(albumIds),
                  csvQuote(resource.path ?? ""),
            ]
            let line = fields.joined(separator: ",")
            f.write(line.data(using: .utf8)!)
            f.write("\n".data(using: .utf8)!)
        }
    }
    
    try f.close()
    print("moving to ", path)
    try w_rename(old: tmp_path, new: path)
    print("done writing csv")
}


func documentPath(filename: String) throws -> String {
    let documentsDirectories = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    if documentsDirectories.count < 1 {
        throw RuntimeError(message: "can't find Documents folder")
    }
    let documentsDirectory = documentsDirectories[0]
    return documentsDirectory.appendingPathComponent(filename).path
}

class AsyncSemaphore {
    
    struct waiter {
        var continuation: CheckedContinuation<Void,Never>
        var next: UnsafeMutablePointer<waiter>?
    }

    struct state {
        var value : Int
        var waitList : UnsafeMutablePointer<waiter>?
    }

    var lock : OSAllocatedUnfairLock<state>
    
    init(value: Int) {
        self.lock = OSAllocatedUnfairLock(initialState: state(value: value))
    }
    
    func wait() async {
        let w = UnsafeMutablePointer<waiter>.allocate(capacity: 1)
        await withCheckedContinuation({ k in
            let done = lock.withLock { s in
                if s.value > 0 {
                    s.value -= 1
                    return true
                } else {
                    w.initialize(to: waiter(continuation: k, next: s.waitList))
                    s.waitList = w
                    return false
                }
            }
            if done {
                k.resume()
            }
        })
        w.deallocate()
    }
    
    func signal() {
        lock.withLock { s in
            if let w = s.waitList {
                s.waitList = w.pointee.next
                w.pointee.continuation.resume()
            } else {
                s.value += 1
            }
        }
    }
}



func getHash(phresource : PHAssetResource) async throws -> (UInt64, SHA256Digest) {
    return try await withCheckedThrowingContinuation { continuation in
        var count : UInt64 = 0
        var hash = SHA256()
        PHAssetResourceManager.default().requestData(for: phresource, options: nil) { data in
            count += UInt64(data.count)
            hash.update(data: data)
        } completionHandler: { e in
            if let e = e {
                continuation.resume(throwing: e)
            } else {
                continuation.resume(returning: (count, hash.finalize()))
            }
        }
    }
}


actor Cache {
    
    var assets : [String:Asset]
    var albums : [String:Album]
    var updateTask : Task<Void,Never>?
    var csv_path : String?
    var limit = AsyncSemaphore(value: 32)
        
    init() {
        self.assets = [:]
        self.albums = [:]
    }
    
    func update(asset : inout Asset?, phasset : PHAsset) async {
        
        let complete = asset?.resources.allSatisfy({ resource in resource.hash != nil && resource.size != nil })

        if complete ?? false,
           let asset = asset,
           let asset_date = asset.modificationDate,
           let phasset_date = phasset.modificationDate,
           asset_date <= phasset_date
        {
            //print("asset", phasset.localIdentifier, "is up to date")
            return
        }
        
        let phresources = PHAssetResource.assetResources(for: phasset)

        var resources = Array<Resource?>(repeating: nil, count: phresources.count)
        
        
        for (i, phresource) in phresources.enumerated()  {
            print("hashing ", phasset.localIdentifier, phresource.originalFilename)
            
            var size : UInt64?
            var hash : SHA256Digest?
            do {
                (size, hash) = try await getHash(phresource: phresource)
            } catch let e {
                print("hashing failed", e)
            }
            
            resources[i] = Resource(
                path: phresource.path,
                size : size,
                hash: hash,
                type: phresource.type,
                filename: phresource.originalFilename,
                uti: phresource.uniformTypeIdentifier)

        }

        
        asset = Asset(id: phasset.localIdentifier,
                      creationDate: phasset.creationDate,
                      modificationDate: phasset.modificationDate,
                      mediaType: phasset.mediaType,
                      mediaSubtypes: phasset.mediaSubtypes,
                      isFavorite: phasset.isFavorite,
                      resources: resources.map({r in r!}))
    }
    
    func update(phasset : PHAsset) async {
        await limit.wait()
        defer { limit.signal() }
        let id = phasset.localIdentifier
        var asset = assets[id]
        await self.update(asset: &asset, phasset: phasset)
        self.assets[id] = asset
    }
    
    func update() async throws {
        if self.csv_path == nil {
            self.csv_path  = try documentPath(filename: "assets.csv")
            self.assets = try readAssetsCSV(path: self.csv_path!)
        }
        
        let albums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        for i in 0..<albums.count {
            let phalbum = albums.object(at: i)
            var ids : Set<String> = []
            let assets = PHAsset.fetchAssets(in: phalbum, options: nil)
            for j in 0..<assets.count {
                let phasset = assets.object(at: j)
                ids.insert(phasset.localIdentifier)
            }
            self.albums[phalbum.localIdentifier] = Album(title: phalbum.localizedTitle, assetIds: ids)
        }
        
        let assets = Photos.PHAsset.fetchAssets(with: PHFetchOptions())        ///

        await withTaskGroup(of: Void.self) { g in
            for i in 0..<assets.count {
                g.addTask {
                    await self.update(phasset: assets.object(at: i))
                }
            }
        }
        
        let needsIds : [String] = self.assets.compactMap { id, asset in
            if asset.cloudid == nil {
                return id
            } else {
                return nil
            }
        }
        let cloudIds = PHPhotoLibrary.shared().cloudIdentifierMappings(forLocalIdentifiers: needsIds)
        for (id, result) in cloudIds {
            switch result {
            case .failure(let e):
                print("failed to get cloud id for \(id): \(e)")
            case.success(let cloudid):
                print("\(id) -> cloud: \(cloudid)")
                self.assets[id]!.cloudid = cloudid
            }
        }



        try writeAssetsCSV(assets: self.assets, albums: self.albums, path: csv_path!)
    }
    
    func startUpdating() {
        if self.updateTask != nil {
            return
        }
        self.updateTask = Task {
            defer { self.updateTask = nil }
            do {
                try await self.update()
                print("update complete.")
            } catch let e {
                print("error updating:", e)
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
    
    var updater : Cache
    
    func createAsset() {
        
        var placeholder : PHObjectPlaceholder?

        PHPhotoLibrary.shared().performChanges({

            let heic = "/Users/larry/Pictures/Photos Library.photoslibrary/originals/F/F96A88FF-8492-49BA-B891-9508A71AFCA6.heic"
            let mov = "/Users/larry/Pictures/Photos Library.photoslibrary/originals/F/F96A88FF-8492-49BA-B891-9508A71AFCA6_3.mov"

            let opts1 = PHAssetResourceCreationOptions()
//            opts1.uniformTypeIdentifier = "public.heic"
            opts1.originalFilename = "lol.HEIC"
//
            let opts2 = PHAssetResourceCreationOptions()
//            opts2.originalFilename = "LOL.mov"
//            opts1.uniformTypeIdentifier = "com.apple.quicktime-movie"
            
            let req = PHAssetCreationRequest.forAsset()
            req.addResource(with: .photo, fileURL: URL(fileURLWithPath: heic), options: opts1)
            req.addResource(with: .pairedVideo, fileURL: URL(fileURLWithPath: mov), options: opts2)
            placeholder = req.placeholderForCreatedAsset


        }, completionHandler:{ ok,err in
            print("!!!", ok, err as Any, placeholder?.localIdentifier ?? "nil")
        })
    }


    func gotAuthorization(_ status:PHAuthorizationStatus) {
        if status != .authorized {
            print("==not authorized :(")
            return
        }
        print ("==got authorization.")

        Task { await updater.startUpdating() }
        
        //createAsset()

    }
        
            
    init() {
        self.updater = Cache()
        if PHPhotoLibrary.authorizationStatus(for: .readWrite) != .authorized {
            print("==requesting authorization.....")
            Photos.PHPhotoLibrary.requestAuthorization(for: .readWrite, handler:self.gotAuthorization)
        } else {
            self.gotAuthorization(.authorized)
        }
    }
}
