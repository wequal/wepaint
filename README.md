# WePaint

A Windows 11 Paint–style raster editor for iPhone, iPad and Mac, written in Swift with SwiftUI and a Core Graphics canvas.

## Features

**Tools**
- Pencil (hard-edged), Eraser (erases to Color 2 on the background layer, to transparent on other layers)
- Brushes: brush, two calligraphy brushes, airbrush, oil brush, crayon, marker, natural pencil, watercolor (Apple Pencil pressure aware)
- Fill with color (flood fill with tolerance), Color picker (eyedropper), Magnifier
- Text with font, size, bold / italic / underline / strikethrough, alignment and opaque background
- Shapes: line, curve, oval, rectangle, rounded rectangle, polygon, triangles, diamond, pentagon, hexagon, arrows, stars, callouts, heart, lightning — with outline / fill options; shapes stay editable (move / resize handles) until committed

**Selection**
- Rectangle and free-form selection, transparent selection
- Move, resize, cut / copy / paste, delete, select all, invert, crop to selection
- Rotate 90° / 180°, flip horizontal / vertical, resize and skew the selection

**Image**
- Rotate, flip, resize (percent or pixels), skew, canvas resize
- Transparent background, black-and-white conversion, image properties

**Layers**
- Add, duplicate, delete, merge down, reorder, show / hide, opacity, rename

**Workflow**
- Unlimited-ish undo / redo, pinch zoom (12.5 %–800 %), gridlines, status bar with cursor position and selection size
- Open from Photos or Files, paste from the clipboard or a file, export PNG / JPEG, save to Photos, share sheet
- Right-click paints with Color 2 on Mac / iPad with a pointer; keyboard shortcuts for the common commands

## Platforms

| Platform | Minimum | Layout |
| --- | --- | --- |
| iPhone | iOS 17 | Compact toolbar with sheets |
| iPad | iPadOS 17 | Ribbon + layers sidebar, Apple Pencil and trackpad support |
| Mac | macOS 14 (Mac Catalyst) | Ribbon + layers sidebar, menu bar commands, pointer cursors |

## Building

Requirements: Xcode 16 or later.

```bash
git clone git@github.com:wequal/wepaint.git
cd wepaint
open WePaint.xcodeproj
```

Select the **WePaint** scheme and a simulator, device or *My Mac (Mac Catalyst)* destination, then Run.

From the command line:

```bash
# iOS Simulator
xcodebuild -scheme WePaint -destination 'platform=iOS Simulator,name=iPhone 17' build

# Mac Catalyst
xcodebuild -scheme WePaint -destination 'platform=macOS,variant=Mac Catalyst' build
```

To run on a physical device, set your development team under *Signing & Capabilities* with *Automatically manage signing* enabled.

## Tests

`WePaintUITests` drives the app with real taps and drags and verifies results by sampling screen pixels and app state:

```bash
xcodebuild -scheme WePaint -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## Architecture

```
WePaint/
├── App/        WePaintApp (scene + menu commands), ContentView (adaptive layout)
├── Model/      PaintDocument, RasterLayer (RGBA8 bitmaps), HistoryManager, Selection
├── Canvas/     CanvasView (UIKit raster canvas + touch routing), CanvasContainer (scroll/zoom host, overlay)
├── Tools/      Tool protocol, stroke tools, fill / picker / magnifier, shapes, text, selection
├── Image/      Rotate / flip / resize / skew / canvas operations
├── IO/         Import, export, Photos, FileDocument wrapper
└── UI/         Ribbon, compact toolbar, tool options, palette, layers panel, status bar, dialogs
```

- Each layer is a premultiplied RGBA8 bitmap backed by a top-left-origin `CGContext`, so fill, eraser and selection operate on pixels like Paint.
- Tools receive touches in canvas coordinates from `CanvasView`; in-progress work (pending shapes, marquees, handles) is drawn on a non-zooming overlay for crisp handles at any zoom.
- Undo / redo stores before / after snapshots of the dirty rectangle for pixel edits and closures for structural changes (layers, canvas size).
- Floating selections are lifted off the layer, transformed in place and baked back as a single undo step.

## Not included

AI features of Windows Paint (Cocreator, background removal, generative erase), a layered project file format (export is flattened), and printing.
