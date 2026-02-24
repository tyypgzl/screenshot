# Screenshot

A lightweight, fast macOS menu bar app for capturing screenshots and annotating them — built with Swift, AppKit, and ScreenCaptureKit.

## Features

- **Region Capture** — Select any area of your screen with a crosshair overlay
- **8 Annotation Tools** — Rectangle, Circle, Arrow, Pen, Text, Highlight, Badge, and Select
- **Rotate & Resize** — Grab corners to resize, use the rotation handle to rotate any annotation
- **Color Palette** — 30-color picker with reds, greens, blues, purples, pastels, and grays
- **Adjustable Line Width** — Slider from 1px to 20px
- **Instant Copy & Save** — Copy to clipboard (⌘C) or save to Desktop (⌘S) in one keystroke
- **Menu Bar App** — Lives in your menu bar, no Dock icon clutter
- **Global Hotkey** — Trigger capture from anywhere with `⌘⇧8`
- **Multi-Monitor Support** — Works across all connected displays
- **Undo / Redo** — Full undo/redo history for annotations (⌘Z / ⇧⌘Z)
- **Retina Ready** — Exports at full Retina resolution

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon or Intel Mac

## Installation

### Homebrew (coming soon)

```bash
brew install --cask screenshot
```

### Manual

1. Download the latest `.dmg` from [Releases](https://github.com/tyypgzl/screenshot/releases)
2. Drag **Screenshot.app** to your Applications folder
3. Launch from Applications — it will appear in your menu bar

## Usage

### Quick Start

1. Click the Screenshot icon in the menu bar, or press `⌘⇧8`
2. Click and drag to select a region
3. Annotate using the bottom toolbar
4. Press `⌘C` to copy or `⌘S` to save to Desktop

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘⇧8` | Take Screenshot (global) |
| `⌘C` | Copy to Clipboard + Close |
| `⌘S` | Save to Desktop + Close |
| `⌘Z` | Undo |
| `⇧⌘Z` | Redo |
| `⌫` | Delete Selected Annotation |
| `Esc` | Cancel Text Edit / Switch to Select / Close |

### Tool Shortcuts

| Key | Tool |
|-----|------|
| `V` | Select |
| `R` | Rectangle |
| `C` | Circle |
| `A` | Arrow |
| `P` | Pen |
| `T` | Text |
| `H` | Highlight |
| `B` | Badge |

### Annotations

- **Rectangle / Circle** — Click and drag to draw. Resize from corners, rotate with the handle above.
- **Arrow** — Click and drag from start to end. Grab endpoints to adjust.
- **Pen** — Freehand drawing. Adjust line width with the slider.
- **Text** — Click to place a text field. Type your text and press Enter to commit, Esc to cancel.
- **Highlight** — Semi-transparent overlay. Great for emphasizing areas.
- **Badge** — Numbered circles, auto-incrementing. Perfect for step-by-step guides.

## Building from Source

### Prerequisites

- Xcode 15.0+
- macOS 13.0+ SDK

### Build

```bash
git clone https://github.com/tyypgzl/screenshot.git
cd screenshot
open Screenshot.xcodeproj
```

Then press `⌘R` in Xcode to build and run.

Or build from the command line:

```bash
xcodebuild -scheme Screenshot -configuration Release build
```

## Architecture

```
Screenshot/
├── ScreenshotApp.swift          # App entry point, MenuBarExtra
├── AppModel.swift               # Central state management
├── ContentView.swift            # Main window content
├── Managers/
│   ├── CaptureManager.swift     # ScreenCaptureKit integration
│   ├── ClipboardManager.swift   # Clipboard operations
│   ├── ExportManager.swift      # File export (PNG/JPG)
│   ├── HotkeyManager.swift      # Global hotkey (Carbon)
│   ├── LayerManager.swift       # Layer/undo management
│   └── SettingsManager.swift    # UserDefaults persistence
├── Models/
│   ├── AnnotationTypes.swift    # Annotation data models
│   └── Layers.swift             # Layer model definitions
├── Views/
│   ├── EditorView.swift         # SwiftUI editor view
│   └── ToolPanelView.swift      # Floating toolbars (AppKit)
└── Windows/
    ├── EditorWindow.swift       # Editor window controller
    ├── OverlaySelectionWindow.swift  # Fullscreen selection overlay
    └── ShortcutsWindow.swift    # Shortcuts reference
```

## Tech Stack

- **SwiftUI** + **AppKit** — Hybrid UI for maximum control
- **ScreenCaptureKit** — Modern screen capture API
- **Carbon HIToolbox** — Global hotkey registration
- **CoreImage** — Image processing

## License

MIT License — see [LICENSE](LICENSE) for details.

## Author

Built by [Tayyip Guzel](https://github.com/tyypgzl)
