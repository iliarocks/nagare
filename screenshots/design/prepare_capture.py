#!/usr/bin/env python3
"""Stage the current app in an isolated build directory; never patch product sources."""
import shutil
import subprocess
from pathlib import Path

design = Path(__file__).resolve().parent
repo = design.parent.parent
app = "Nagare" if (repo / "Nagare.xcodeproj").exists() else "Oto"
stage = repo / ".build" / "ScreenshotCaptureSource"
if stage.exists():
    shutil.rmtree(stage)
stage.mkdir(parents=True)
tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=repo).decode().split("\0")
for name in filter(None, tracked):
    if name.startswith(("screenshots/", ".build/")):
        continue
    source, target = repo / name, stage / name
    if source.is_file():
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
shutil.copy2(design / "CaptureScreenshots.swift", stage / f"{app}UITests/AppStoreCaptureTests.swift")

if app == "Nagare":
    for folder in ["Shared/Domain", "Shared/Infrastructure"]:
        (stage / folder).mkdir(parents=True, exist_ok=True)
    source = stage / "Nagare/App/NagareApp.swift"
    contents = source.read_text()
    marker = '        guard arguments.contains("--reset-and-seed-reorder-ui-test") else {'
    assert contents.count(marker) == 1, "Capture insertion point changed; inspect before proceeding."
    contents = contents.replace(marker, (design / "CaptureSampleData.swift").read_text() + "\n" + marker)
    assert '"reorder-regression.store"' in contents
    contents = contents.replace('"reorder-regression.store"', '"app-store-capture.store"')
    source.write_text(contents)
    for name in ["Today", "Upcoming"]:
        source = stage / f"Nagare/Features/{name}/{name}View.swift"
        contents = source.read_text()
        marker = 'if ProcessInfo.processInfo.arguments.contains("--use-reorder-ui-test-store") {'
        assert marker in contents, "Test overlay changed; inspect before proceeding."
        source.write_text(contents.replace(marker, "if false && " + marker[3:]))
print(stage)
