import AppKit
import CoreGraphics
import Foundation
import Photos

struct PhotoImageRequestFailure: Error, Equatable {
    let type: OCRFailureType
    let reason: String
}

struct PhotoLibraryService {
    private let photoPrivacySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos"
    )

    func authorizationState() -> PhotoLibraryAuthorizationState {
        PhotoLibraryAuthorizationState(status: PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestAuthorization() async -> PhotoLibraryAuthorizationState {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: PhotoLibraryAuthorizationState(status: status))
            }
        }
    }

    @discardableResult
    func openPhotoPrivacySettings() -> Bool {
        guard let photoPrivacySettingsURL else {
            return false
        }

        return NSWorkspace.shared.open(photoPrivacySettingsURL)
    }

    func fetchImageAssets(in scope: PhotoLibraryTimeScope) -> [PHAsset] {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        if let startDate = scope.startDate() {
            options.predicate = NSPredicate(format: "creationDate >= %@", startDate as NSDate)
        }
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)
        ]

        let result = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)

        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        return assets
    }

    func fetchImageAsset(localIdentifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
    }

    func summary(for asset: PHAsset) -> PhotoAssetSummary {
        PhotoAssetSummary(
            id: asset.localIdentifier,
            creationDate: asset.creationDate,
            mediaTypeDescription: mediaTypeDescription(for: asset),
            mediaSubtypeDescription: mediaSubtypeDescription(for: asset),
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight
        )
    }

    func requestThumbnail(for asset: PHAsset, targetSize: CGSize) async -> PhotoThumbnail {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                if isDegraded {
                    return
                }

                if let image {
                    continuation.resume(
                        returning: PhotoThumbnail(
                            id: asset.localIdentifier,
                            image: image,
                            failureReason: nil
                        )
                    )
                    return
                }

                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) == true
                let error = info?[PHImageErrorKey] as? Error
                let reason: String

                if let error {
                    reason = "缩略图读取失败：\(error.localizedDescription)"
                } else if isInCloud {
                    reason = "iCloud 图片暂时无法下载缩略图"
                } else {
                    reason = "缩略图读取失败，系统未返回图片"
                }

                continuation.resume(
                    returning: PhotoThumbnail(
                        id: asset.localIdentifier,
                        image: nil,
                        failureReason: reason
                    )
                )
            }
        }
    }

    func requestImageForOCR(for asset: PHAsset, maxPixelSize: CGFloat = 1600) async -> Result<CGImage, PhotoImageRequestFailure> {
        let targetSize = ocrTargetSize(for: asset, maxPixelSize: maxPixelSize)
        let resizedResult = await requestCGImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            deliveryMode: .opportunistic,
            decodeFailureMessage: "图片已返回，但无法转换为 OCR 所需的 CGImage。"
        )

        if case .success = resizedResult {
            return resizedResult
        }

        let originalResult = await requestOriginalCGImage(for: asset)
        if case .success = originalResult {
            return originalResult
        }

        return resizedResult
    }

    func requestPreviewImage(for asset: PHAsset, maxPixelSize: CGFloat = 1800) async -> PhotoThumbnail {
        let targetSize = ocrTargetSize(for: asset, maxPixelSize: maxPixelSize)
        let result = await requestNSImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            deliveryMode: .opportunistic
        )

        switch result {
        case .success(let image):
            return PhotoThumbnail(id: asset.localIdentifier, image: image, failureReason: nil)
        case .failure(let failure):
            return PhotoThumbnail(id: asset.localIdentifier, image: nil, failureReason: failure.reason)
        }
    }

    private func requestCGImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        deliveryMode: PHImageRequestOptionsDeliveryMode,
        decodeFailureMessage: String
    ) async -> Result<CGImage, PhotoImageRequestFailure> {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = deliveryMode
            options.resizeMode = .exact
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: contentMode,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                if isDegraded {
                    return
                }

                if let image {
                    var proposedRect = CGRect(origin: .zero, size: image.size)
                    if let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
                        continuation.resume(returning: .success(cgImage))
                        return
                    }

                    continuation.resume(
                        returning: .failure(
                            PhotoImageRequestFailure(
                                type: .imageDecodeFailed,
                                reason: decodeFailureMessage
                            )
                        )
                    )
                    return
                }

                let wasCancelled = (info?[PHImageCancelledKey] as? Bool) == true
                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) == true
                let error = info?[PHImageErrorKey] as? Error

                if wasCancelled {
                    continuation.resume(
                        returning: .failure(
                            PhotoImageRequestFailure(type: .cancelled, reason: "图片读取任务已取消。")
                        )
                    )
                } else if let error {
                    continuation.resume(
                        returning: .failure(
                            PhotoImageRequestFailure(
                                type: .imageUnavailable,
                                reason: "图片读取失败：\(error.localizedDescription)"
                            )
                        )
                    )
                } else if isInCloud {
                    continuation.resume(
                        returning: .failure(
                            PhotoImageRequestFailure(
                                type: .imageUnavailable,
                                reason: "iCloud 图片暂时无法下载用于 OCR 的预览图。"
                            )
                        )
                    )
                } else {
                    continuation.resume(
                        returning: .failure(
                            PhotoImageRequestFailure(
                                type: .imageUnavailable,
                                reason: "图片读取失败，系统未返回可识别图片。"
                            )
                        )
                    )
                }
            }
        }
    }

    private func requestNSImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        deliveryMode: PHImageRequestOptionsDeliveryMode
    ) async -> Result<NSImage, PhotoImageRequestFailure> {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = deliveryMode
            options.resizeMode = .exact
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: contentMode,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                if isDegraded {
                    return
                }

                if let image {
                    continuation.resume(returning: .success(image))
                    return
                }

                continuation.resume(returning: .failure(Self.imageRequestFailure(from: info)))
            }
        }
    }

    private func requestOriginalCGImage(for asset: PHAsset) async -> Result<CGImage, PhotoImageRequestFailure> {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                guard let data, let image = NSImage(data: data) else {
                    continuation.resume(returning: .failure(Self.imageRequestFailure(from: info)))
                    return
                }

                var proposedRect = CGRect(origin: .zero, size: image.size)
                guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
                    continuation.resume(
                        returning: .failure(
                            PhotoImageRequestFailure(
                                type: .imageDecodeFailed,
                                reason: "已读取原图数据，但无法转换为 OCR 所需的 CGImage。"
                            )
                        )
                    )
                    return
                }

                continuation.resume(returning: .success(cgImage))
            }
        }
    }

    private static func imageRequestFailure(from info: [AnyHashable: Any]?) -> PhotoImageRequestFailure {
        let wasCancelled = (info?[PHImageCancelledKey] as? Bool) == true
        let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) == true
        let error = info?[PHImageErrorKey] as? Error

        if wasCancelled {
            return PhotoImageRequestFailure(type: .cancelled, reason: "图片读取任务已取消。")
        }

        if let error {
            return PhotoImageRequestFailure(
                type: .imageUnavailable,
                reason: "图片读取失败：\(error.localizedDescription)"
            )
        }

        if isInCloud {
            return PhotoImageRequestFailure(
                type: .imageUnavailable,
                reason: "iCloud 图片暂时无法下载用于本地处理。"
            )
        }

        return PhotoImageRequestFailure(
            type: .imageUnavailable,
            reason: "图片读取失败，系统未返回可处理图片。"
        )
    }

    func loadEmbeddingValidationSamples(
        from descriptors: [EmbeddingValidationSampleDescriptor],
        maxPixelSize: CGFloat = 1600
    ) async -> EmbeddingValidationSampleLoadResult {
        await EmbeddingValidationSampleLoader.loadSamples(from: descriptors) { localIdentifier in
            guard let asset = fetchImageAsset(localIdentifier: localIdentifier) else {
                return .failure("Photos 中未找到该验证样本图片，可能已被删除或当前授权范围不可访问。")
            }

            let imageResult = await requestImageForOCR(for: asset, maxPixelSize: maxPixelSize)
            switch imageResult {
            case .success(let image):
                return .success(image)
            case .failure(let failure):
                return .failure(failure.reason)
            }
        }
    }

    private func mediaTypeDescription(for asset: PHAsset) -> String {
        switch asset.mediaType {
        case .image:
            return "照片"
        default:
            return "其他"
        }
    }

    private func ocrTargetSize(for asset: PHAsset, maxPixelSize: CGFloat) -> CGSize {
        let width = CGFloat(max(asset.pixelWidth, 1))
        let height = CGFloat(max(asset.pixelHeight, 1))
        let longestSide = max(width, height)
        let scale = min(maxPixelSize / longestSide, 1)

        return CGSize(width: width * scale, height: height * scale)
    }

    private func mediaSubtypeDescription(for asset: PHAsset) -> String {
        var subtypes: [String] = []
        if asset.mediaSubtypes.contains(.photoScreenshot) {
            subtypes.append("截图")
        }
        if asset.mediaSubtypes.contains(.photoLive) {
            subtypes.append("Live Photo")
        }
        if asset.mediaSubtypes.contains(.photoPanorama) {
            subtypes.append("全景")
        }
        if asset.mediaSubtypes.contains(.photoHDR) {
            subtypes.append("HDR")
        }

        return subtypes.isEmpty ? "普通图片" : subtypes.joined(separator: "、")
    }
}
