# Screenshots

- `originals/`: untouched captures, grouped into iPhone, Website, and (for Nagare) Mac.
- `app-store/`: finished upload images, grouped by platform and numbered in order.
- `design/`: capture tools, layout, official Apple frame, and capture manifest.
- `../docs/assets/`: full-resolution website copies, served by GitHub Pages.

## Rebuild

From the repository root, with a full Xcode installation selected:

```sh
python3 screenshots/design/prepare_capture.py
# Run the capture tests in .build/ScreenshotCaptureSource, then export:
python3 screenshots/design/export_captures.py PATH_TO_RESULT.xcresult iPhone
swift screenshots/design/render.swift screenshots/design/layout.json iPhone
```

The compositor reads originals and writes finished designs. It uses the official iPhone 17 White frame and slate background, with no captions. Original iPhone captures are 1206 × 2622; App Store canvases are 1320 × 2868. Screen content is scaled proportionally without enlargement. Website images retain original resolution. Reduced contact sheets are for overview only; inspect originals or finished images for typography.

Generated previews and temporary review galleries are excluded from Git. Capture metadata and image checksums are in `design/capture-manifest.json`.
