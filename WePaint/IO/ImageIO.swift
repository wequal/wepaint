import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case png, jpeg

    var id: String { rawValue }
    var title: String { self == .png ? "PNG picture" : "JPEG picture" }
    var fileExtension: String { self == .png ? "png" : "jpg" }
    var contentType: UTType { self == .png ? .png : .jpeg }
}

enum ImageIO {
    static let importTypes: [UTType] = [.png, .jpeg, .bmp, .gif, .tiff, .heic, .heif, .image]

    static func loadImage(from url: URL) -> CGImage? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return loadImage(from: data)
    }

    static func loadImage(from data: Data) -> CGImage? {
        UIImage(data: data)?.normalizedCGImage()
    }

    static func encode(_ image: CGImage, format: ExportFormat, quality: CGFloat = 0.92) -> Data? {
        let ui = UIImage(cgImage: image)
        switch format {
        case .png: return ui.pngData()
        case .jpeg: return ui.jpegData(compressionQuality: quality)
        }
    }

    static func saveToPhotos(_ data: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "WePaint", code: 1,
                                                userInfo: [NSLocalizedDescriptionKey: "Photo library access was not granted."])))
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }) { success, error in
                DispatchQueue.main.async {
                    if success { completion(.success(())) } else {
                        completion(.failure(error ?? NSError(domain: "WePaint", code: 2,
                                                             userInfo: [NSLocalizedDescriptionKey: "Unable to save to Photos."])))
                    }
                }
            }
        }
    }
}

/// A flattened image ready to be written by `fileExporter`.
struct ExportedImageFile: FileDocument {
    static var readableContentTypes: [UTType] { [.png, .jpeg] }
    static var writableContentTypes: [UTType] { [.png, .jpeg] }

    var data: Data
    var format: ExportFormat

    init(data: Data, format: ExportFormat) {
        self.data = data
        self.format = format
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        format = configuration.contentType == .jpeg ? .jpeg : .png
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension PaintDocument {
    /// Produces the exportable bytes for the current image.
    func exportData(format: ExportFormat) -> Data? {
        toolHost?.commitPendingToolWork()
        let background: RGBA? = format == .jpeg ? .white : nil
        guard let img = flattenedImage(background: background) else { return nil }
        return ImageIO.encode(img, format: format)
    }

    var exportBaseName: String {
        let base = (fileName as NSString).deletingPathExtension
        return base.isEmpty ? "Untitled" : base
    }
}
