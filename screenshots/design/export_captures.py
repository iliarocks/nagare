#!/usr/bin/env python3
"""Export original XCTest attachment bytes to originals/, preserving all image pixels."""
import argparse
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("result", type=Path, help="Successful .xcresult bundle")
parser.add_argument("platform", choices=["iPhone", "Mac"])
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
config = json.loads((root / "Design/layout.json").read_text())
pages = next(s["pages"] for s in config["sets"] if s["platform"] == args.platform)
with tempfile.TemporaryDirectory(prefix="app-store-captures-") as temporary:
    export = Path(temporary)
    subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(args.result.resolve()), "--output-path", str(export), "--test-id", "AppStoreCaptureTests/testCaptureFourPages()"], check=True)
    found = {}
    for test in json.loads((export / "manifest.json").read_text()):
        for attachment in test["attachments"]:
            page = attachment["suggestedHumanReadableName"].split("_0_")[0]
            if page in pages:
                found[page] = export / attachment["exportedFileName"]
    assert set(found) == set(pages), "Result does not contain all four captures. Raw files were not changed."
    target = root / "originals" / args.platform
    target.mkdir(parents=True, exist_ok=True)
    for page in pages:
        shutil.copy2(found[page], target / f"{page}.png")
print(f"Exported {len(pages)} unmodified captures to {target}")
