"""Runs real Home UI tests on disposable simulators; never signs or publishes."""
import json
import os
from pathlib import Path
import shutil
import subprocess


def run(*args):
    return subprocess.check_output(args, text=True).strip()


temp = Path(os.environ["RUNNER_TEMP"])
derived = temp / "CaptroBuild"
output = temp / "home-full-bleed"
output.mkdir(exist_ok=True)
inventory = json.loads(run("xcrun", "simctl", "list", "-j"))
runtime = next(r["identifier"] for r in reversed(inventory["runtimes"])
               if r.get("isAvailable") and "iOS" in r["name"])
device_types = {d["name"]: d["identifier"] for d in inventory["devicetypes"]}
names = ["iPhone SE (3rd generation)", "iPhone 17 Pro Max"]
for name in names:
    if name not in device_types:
        raise RuntimeError(f"Required simulator type is unavailable: {name}")

video = temp / "full-bleed-fixture.mp4"
subprocess.run([
    "ffmpeg", "-v", "error", "-f", "lavfi", "-i",
    "color=c=0x1494a3:s=720x960:r=12,drawbox=x=iw*0.4:y=0:w=iw*0.2:h=ih:color=0xf03d6e:t=fill",
    "-t", "4", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-y", str(video),
], check=True)

for index, name in enumerate(names):
    device = run("xcrun", "simctl", "create", f"Captro full bleed {index}", device_types[name], runtime)
    result = output / f"device-{index}.xcresult"
    try:
        subprocess.run(["xcrun", "simctl", "boot", device], check=True)
        subprocess.run(["xcrun", "simctl", "bootstatus", device, "-b"], check=True)
        base = ["xcodebuild", "-project", "Captro.xcodeproj", "-scheme", "Captro", "-configuration", "Debug",
                "-destination", f"platform=iOS Simulator,id={device}", "-derivedDataPath", str(derived),
                "CODE_SIGNING_ALLOWED=NO"]
        if index == 0:
            subprocess.run(base + ["build-for-testing"], check=True)
        app = derived / "Build/Products/Debug-iphonesimulator/Captro.app"
        subprocess.run(["xcrun", "simctl", "install", device, str(app)], check=True)
        container = Path(run("xcrun", "simctl", "get_app_container", device, "com.captro.app", "data"))
        (container / "Documents").mkdir(exist_ok=True)
        shutil.copy2(video, container / "Documents/full-bleed-fixture.mp4")
        tested = subprocess.run(base + ["test-without-building", "-parallel-testing-enabled", "NO",
                                       "-resultBundlePath", str(result)])
        attachments = output / f"screenshots-{index}"
        subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result),
                        "--output-path", str(attachments)], check=True)
        tested.check_returncode()
    finally:
        subprocess.run(["xcrun", "simctl", "shutdown", device], check=False)
        subprocess.run(["xcrun", "simctl", "delete", device], check=False)
