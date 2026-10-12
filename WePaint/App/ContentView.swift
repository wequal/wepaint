import SwiftUI

struct ContentView: View {
    @Environment(PaintDocument.self) private var doc
    @Environment(AppUIState.self) private var ui
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        @Bindable var ui = ui
        Group {
            if hSize == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .fileOperations(ui: ui, document: doc)
        .sheet(isPresented: $ui.showLayersSheet) {
            NavigationStack {
                LayersPanel()
                    .navigationTitle("Layers")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { ui.showLayersSheet = false } } }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $ui.showColorsSheet) { ColorsSheet() }
        .sheet(isPresented: $ui.showToolOptionsSheet) { ToolOptionsSheet() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            doc.toolHost?.commitPendingToolWork()
        }
    }

    private var canvas: some View {
        CanvasContainer(document: doc, fingerPans: ui.fingerPans)
            .ignoresSafeArea(.keyboard)
    }

    // MARK: iPad

    private var regularLayout: some View {
        VStack(spacing: 0) {
            RibbonView()
            Divider()
            ToolOptionsBar()
            Divider()
            HStack(spacing: 0) {
                canvas
                if doc.showLayersPanel {
                    Divider()
                    LayersPanel().frame(width: 240)
                }
            }
            if doc.showStatusBar {
                Divider()
                StatusBar()
            }
        }
    }

    // MARK: iPhone

    private var compactLayout: some View {
        VStack(spacing: 0) {
            CompactTopBar()
            Divider()
            canvas
            Divider()
            ToolOptionsBar(compact: true)
            Divider()
            CompactToolbar()
            if doc.showStatusBar {
                Divider()
                StatusBar(compact: true)
            }
        }
    }
}
