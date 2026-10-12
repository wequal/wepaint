import PhotosUI
import SwiftUI

enum ImportPurpose {
    case open, pasteFrom
}

struct AlertInfo: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

/// Presentation state shared by the ribbon, menus, keyboard commands and sheets.
@Observable
final class AppUIState {
    var showPhotosPicker = false
    var photoItem: PhotosPickerItem?
    var showFileImporter = false
    var importPurpose: ImportPurpose = .open

    var showExporter = false
    var exportFile: ExportedImageFile?
    var exportFormat: ExportFormat = .png

    var showResizeSkew = false
    var showProperties = false
    var showLayersSheet = false
    var showColorsSheet = false
    var showToolOptionsSheet = false
    var showZoomSheet = false

    var alert: AlertInfo?
    var showUnsavedDialog = false
    var pendingAction: (() -> Void)?
    var fingerPans = false

    // MARK: - Guarded actions

    func performDiscardable(_ document: PaintDocument, _ action: @escaping () -> Void) {
        if document.isDirty {
            pendingAction = action
            showUnsavedDialog = true
        } else {
            action()
        }
    }

    func newImage(_ document: PaintDocument) {
        performDiscardable(document) {
            document.newDocument(size: PaintDocument.defaultSize)
        }
    }

    func openFromPhotos(_ document: PaintDocument, purpose: ImportPurpose) {
        importPurpose = purpose
        let present = { [self] in showPhotosPicker = true }
        if purpose == .open { performDiscardable(document, present) } else { present() }
    }

    func openFromFiles(_ document: PaintDocument, purpose: ImportPurpose) {
        importPurpose = purpose
        let present = { [self] in showFileImporter = true }
        if purpose == .open { performDiscardable(document, present) } else { present() }
    }

    func exportImage(_ document: PaintDocument, format: ExportFormat) {
        guard let data = document.exportData(format: format) else {
            alert = AlertInfo(title: "Unable to save", message: "The image could not be encoded.")
            return
        }
        exportFormat = format
        exportFile = ExportedImageFile(data: data, format: format)
        showExporter = true
    }

    func saveToPhotos(_ document: PaintDocument) {
        guard let data = document.exportData(format: .png) else { return }
        ImageIO.saveToPhotos(data) { [weak self] result in
            switch result {
            case .success:
                document.isDirty = false
                self?.alert = AlertInfo(title: "Saved", message: "The image was saved to your Photos library.")
            case .failure(let error):
                self?.alert = AlertInfo(title: "Unable to save", message: error.localizedDescription)
            }
        }
    }

    func handleImported(image: CGImage?, name: String, document: PaintDocument) {
        guard let image else {
            alert = AlertInfo(title: "Unable to open", message: "That file does not contain a supported image.")
            return
        }
        switch importPurpose {
        case .open:
            document.load(image: image, name: name)
        case .pasteFrom:
            document.pasteImage(image)
        }
    }

    func handle(photoItem: PhotosPickerItem?, document: PaintDocument) {
        guard let photoItem else { return }
        Task { @MainActor in
            let data = try? await photoItem.loadTransferable(type: Data.self)
            let image = data.flatMap { ImageIO.loadImage(from: $0) }
            handleImported(image: image, name: "Photo", document: document)
            self.photoItem = nil
        }
    }

    func handle(fileResult: Result<URL, Error>, document: PaintDocument) {
        switch fileResult {
        case .success(let url):
            handleImported(image: ImageIO.loadImage(from: url), name: url.lastPathComponent, document: document)
        case .failure(let error):
            alert = AlertInfo(title: "Unable to open", message: error.localizedDescription)
        }
    }
}

/// Attaches the pickers, exporters, alerts and sheets to a view.
struct FileOperationsModifier: ViewModifier {
    @Bindable var ui: AppUIState
    let document: PaintDocument

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $ui.showPhotosPicker, selection: $ui.photoItem, matching: .images)
            .onChange(of: ui.photoItem) { _, item in ui.handle(photoItem: item, document: document) }
            .fileImporter(isPresented: $ui.showFileImporter, allowedContentTypes: ImageIO.importTypes) { result in
                ui.handle(fileResult: result, document: document)
            }
            .fileExporter(isPresented: $ui.showExporter, document: ui.exportFile, contentType: ui.exportFormat.contentType,
                          defaultFilename: document.exportBaseName) { result in
                if case .success = result { document.isDirty = false }
                if case .failure(let error) = result {
                    ui.alert = AlertInfo(title: "Unable to save", message: error.localizedDescription)
                }
            }
            .alert(item: $ui.alert) { info in
                Alert(title: Text(info.title), message: Text(info.message), dismissButton: .default(Text("OK")))
            }
            .confirmationDialog("Do you want to save changes to \(document.fileName)?", isPresented: $ui.showUnsavedDialog, titleVisibility: .visible) {
                Button("Save as PNG…") {
                    ui.pendingAction = nil
                    ui.exportImage(document, format: .png)
                }
                Button("Don't Save", role: .destructive) {
                    let action = ui.pendingAction
                    ui.pendingAction = nil
                    action?()
                }
                Button("Cancel", role: .cancel) { ui.pendingAction = nil }
            }
            .sheet(isPresented: $ui.showResizeSkew) {
                ResizeSkewSheet(document: document)
            }
            .sheet(isPresented: $ui.showProperties) {
                ImagePropertiesSheet(document: document)
            }
    }
}

extension View {
    func fileOperations(ui: AppUIState, document: PaintDocument) -> some View {
        modifier(FileOperationsModifier(ui: ui, document: document))
    }
}
