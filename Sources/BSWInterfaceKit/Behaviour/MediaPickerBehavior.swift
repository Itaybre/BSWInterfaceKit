//
//  Created by Pierluigi Cifani on 08/08/16.
//  Copyright © 2018 TheLeftBit SL. All rights reserved.
//
#if canImport(UIKit)

import UIKit
import MobileCoreServices
import ImageIO
import AVFoundation
import Photos
import UniformTypeIdentifiers
import PhotosUI

public typealias MediaHandler = ((URL?) -> Void)

@available(tvOS, unavailable)
final public class MediaPickerBehavior: NSObject, UIDocumentPickerDelegate, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    public enum Kind {
        case photo
        case video
        case thumbnail(CGSize)
        
        func pathExtension() -> String {
            switch self {
            case .photo, .thumbnail:
                return "jpeg"
            case .video:
                return "mov"
            }
        }
        
        var contentTypes: [UTType] {
            switch self {
            case .photo, .thumbnail:
                return [UTType.image, UTType.jpeg, UTType.png]
            case .video:
                return [UTType.movie, UTType.video, UTType.quickTimeMovie]
            }
        }
    }
    
    public enum Source {
        case photoAlbum
        case camera
        case filesApp
    }

    private struct Request {
        let handler: MediaHandler
        let kind: Kind
    }
    
    private var currentRequest: Request?
    private let fileManager = FileManager.default
 
    public func getMedia(_ kind: Kind = .photo, source: Source = .photoAlbum, handler: @escaping MediaHandler) -> UIViewController? {
        
        guard self.currentRequest == nil else {
            handler(nil)
            return nil
        }
        
        self.currentRequest = Request(handler: handler, kind: kind)

        switch source {
        case .filesApp:
            return handleFilesAppRequest(kind: kind, handler: handler)
        case .camera:
            return handleCameraRequest(kind: kind, handler: handler)
        case .photoAlbum:
            return handleImagePickerRequest(kind: kind, handler: handler)
        }
    }
    
    public func createVideoThumbnail(forURL videoURL: URL) async throws -> URL {
        let asset = AVAsset(url: videoURL)
        let durationSeconds = CMTimeGetSeconds(asset.duration)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        
        let time = CMTimeMakeWithSeconds(durationSeconds/3.0, preferredTimescale: 600)
        return try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { (_, thumbnail, _, _, error) in
                guard let thumbnail = thumbnail else {
                    continuation.resume(throwing: Error.unknown)
                    return
                }
                guard error == nil else {
                    continuation.resume(throwing: error!)
                    return
                }
                
                let image = UIImage(cgImage: thumbnail)
                do {
                    let finalURL = try self.writeToCache(image: image, kind: .photo)
                    continuation.resume(returning: finalURL)
                } catch let error {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: UIDocumentPickerDelegate
    
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        defer {
            self.currentRequest = nil
        }
        guard let currentRequest = self.currentRequest, let url = urls.first else { return }
        currentRequest.handler(url)
    }

    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        currentRequest?.handler(nil)
        currentRequest = nil
    }

    // MARK: UIImagePickerControllerDelegate
    
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        guard let currentRequest = self.currentRequest else { return }
        
        defer {
            self.currentRequest = nil
        }
        
        let validMedia: Bool = {
            guard let mediaTypeString = info[.mediaType] as? String else { return false }
            switch currentRequest.kind {
            case .video:
                return mediaTypeString == kUTTypeMovie as String
            case .photo, .thumbnail:
                return mediaTypeString == kUTTypeImage as String
            }
        }()
        
        guard validMedia else {
            self.currentRequest?.handler(nil)
            return
        }
        
        switch currentRequest.kind {
        case .video:
            handleVideoRequest(info: info, request: currentRequest)
        case .photo:
            handlePhotoRequest(info: info, request: currentRequest)
        case .thumbnail:
            handleThumbnailRequest(info: info, request: currentRequest)
        }
    }
        
    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        currentRequest?.handler(nil)
        currentRequest = nil
    }

    // MARK: PHPickerViewControllerDelegate
    
    public func picker(_ p: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard let currentRequest = self.currentRequest, let itemProvider = results.first?.itemProvider else { return }
        defer {
            self.currentRequest = nil
        }
        itemProvider.loadFileRepresentation(forTypeIdentifier: currentRequest.kind.contentTypes.first!.identifier) { url, error in
            guard let url = url else {
                DispatchQueue.main.async {
                    currentRequest.handler(nil)
                }
                return
            }
            let targetURL = Self.createFileURL(input: currentRequest.kind)
            do {
                try FileManager.default.moveItem(at: url, to: targetURL)
                DispatchQueue.main.async {
                    currentRequest.handler(targetURL)
                }
            } catch {
                DispatchQueue.main.async {
                    currentRequest.handler(nil)
                }
            }
        }
    }
    
    // MARK: Private

    private func handleFilesAppRequest(kind: Kind, handler: @escaping MediaHandler) -> UIViewController? {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: kind.contentTypes, asCopy: true)
        vc.delegate = self
        vc.allowsMultipleSelection = false
        return vc
    }

    private func handleCameraRequest(kind: Kind, handler: @escaping MediaHandler) -> UIViewController? {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            handler(nil)
            return nil
        }
        let imagePicker = UIImagePickerController()
        imagePicker.sourceType = .camera
        imagePicker.delegate = self
        imagePicker.cameraDevice = .front
        switch kind {
        case .video:
            imagePicker.mediaTypes = [kUTTypeMovie as String]
        case .photo, .thumbnail:
            imagePicker.mediaTypes = [kUTTypeImage as String]
        }
        return imagePicker
    }
    
    private func handleImagePickerRequest(kind: Kind, handler: @escaping MediaHandler) -> UIViewController? {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = 1
        switch kind {
        case .photo:
            configuration.filter = .any(of: [.livePhotos, .images])
        case .thumbnail:
            if #available(iOS 15.0, *) {
                configuration.filter = .any(of: [.images, .screenshots])
            } else {
                configuration.filter = .images
            }
        case .video:
            if #available(iOS 15.0, *) {
                configuration.filter = .any(of: [.screenRecordings, .videos, .livePhotos])
            } else {
                configuration.filter = .any(of: [.videos, .livePhotos])
            }
        }
        let vc = PHPickerViewController(configuration: configuration)
        vc.delegate = self
        return vc
    }
    
    private func cachePathForMedia(_ kind: Kind) -> URL {
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return cachesDirectory.appendingPathComponent("\(UUID().uuidString).\(kind.pathExtension())")
    }
    
    private func handleVideoRequest(info: [UIImagePickerController.InfoKey : Any], request: Request) {
        if let videoURL = info[.mediaURL] as? URL {
            request.handler(videoURL)
        } else if let asset = info[.phAsset] as? PHAsset {
            let options = PHVideoRequestOptions()
            options.version = .original
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options, resultHandler: {(asset, _, _) -> Void in
                DispatchQueue.main.async {
                    if let urlAsset = asset as? AVURLAsset {
                        request.handler(urlAsset.url)
                    } else {
                        request.handler(nil)
                    }
                }
            })

        } else {
            request.handler(nil)
        }
    }

    private func handlePhotoRequest(info: [UIImagePickerController.InfoKey : Any], request: Request) {
        
        guard let image = info[.originalImage] as? UIImage else {
            self.currentRequest?.handler(nil)
            return
        }
        
        do {
            let finalURL = try writeToCache(image: image, kind: request.kind)
            self.currentRequest?.handler(finalURL)
        } catch {
            self.currentRequest?.handler(nil)
        }
    }
    
    private func handleThumbnailRequest(info: [UIImagePickerController.InfoKey : Any], request: Request) {
        guard case .thumbnail(let size) = request.kind else {
            fatalError()
        }
        
        let _image: UIImage? = {
            var imageSource: CGImageSource!
            if let imageURL = info[.imageURL] as? URL {
                imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil)
            } else if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 1) {
                imageSource = CGImageSourceCreateWithData(data as CFData, nil)
            }
            
            if imageSource == nil {
                return nil
            }
            
            let _ = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)
            let options: [NSString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: size.width,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            
            guard let scaledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
                return nil
            }
            return UIImage(cgImage: scaledImage)
        }()
        
        guard let image = _image else {
            request.handler(nil)
            return
        }
        
        do {
            let url = try writeToCache(image: image, kind: request.kind)
            request.handler(url)
        } catch {
            request.handler(nil)
        }

    }
    
    private func writeToCache(image: UIImage, kind: Kind) throws -> URL {
        guard let data = image.jpegData(compressionQuality: 1) else {
            throw Error.jpegCompressionFailed
        }
        
        let finalURL = cachePathForMedia(kind)
        do {
            try data.write(to: finalURL, options: [.atomic])
            return finalURL
        }
        catch {
            throw Error.diskWriteFailed
        }
    }
    
    enum Error: Swift.Error {
        case jpegCompressionFailed
        case diskWriteFailed
        case unknown
    }
    
    public static func createFileURL(input: Kind) -> URL {
        let cachesPath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cachesPath.appendingPathComponent("\(UUID().uuidString).\(input.pathExtension())")
    }
}
#endif
