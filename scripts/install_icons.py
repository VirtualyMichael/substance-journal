"""Copy the rendered app icon into the Android, iOS and Windows projects and the README.

Render the PNGs first (see app/test/icon_render_test.dart), then:

  python scripts/install_icons.py path/to/rendered/icons
"""
from __future__ import annotations

import shutil
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "app"

ANDROID = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}

# iOS file name -> pixel size (points x scale).
IOS = {
    "Icon-App-20x20@1x": 20, "Icon-App-20x20@2x": 40, "Icon-App-20x20@3x": 60,
    "Icon-App-29x29@1x": 29, "Icon-App-29x29@2x": 58, "Icon-App-29x29@3x": 87,
    "Icon-App-40x40@1x": 40, "Icon-App-40x40@2x": 80, "Icon-App-40x40@3x": 120,
    "Icon-App-60x60@2x": 120, "Icon-App-60x60@3x": 180,
    "Icon-App-76x76@1x": 76, "Icon-App-76x76@2x": 152,
    "Icon-App-83.5x83.5@2x": 167,
    "Icon-App-1024x1024@1x": 1024,
}

ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]


def build_ico(pngs: list[tuple[int, bytes]]) -> bytes:
    """An .ico holding PNG images (supported since Windows Vista)."""
    header = struct.pack("<HHH", 0, 1, len(pngs))
    entries, data, offset = b"", b"", 6 + 16 * len(pngs)
    for size, png in pngs:
        wh = 0 if size >= 256 else size  # 0 means 256
        entries += struct.pack("<BBBBHHII", wh, wh, 0, 0, 1, 32, len(png), offset)
        data += png
        offset += len(png)
    return header + entries + data


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    src = Path(sys.argv[1])

    def rounded(n: int) -> Path:
        return src / f"rounded_{n}.png"

    def square(n: int) -> Path:
        return src / f"square_{n}.png"

    for density, px in ANDROID.items():
        shutil.copyfile(rounded(px), APP / "android/app/src/main/res" / f"mipmap-{density}" / "ic_launcher.png")

    ios = APP / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for name, px in IOS.items():
        shutil.copyfile(square(px), ios / f"{name}.png")

    ico = build_ico([(n, rounded(n).read_bytes()) for n in ICO_SIZES])
    (APP / "windows/runner/resources/app_icon.ico").write_bytes(ico)

    (ROOT / "docs").mkdir(exist_ok=True)
    shutil.copyfile(rounded(512), ROOT / "docs/logo.png")
    print("Installed: Android mipmaps, iOS app icons, Windows app_icon.ico, docs/logo.png")


if __name__ == "__main__":
    main()
