"""Create a small Windows upgrade ZIP without copying multi-gigabyte models."""

from __future__ import annotations

import argparse
import zipfile
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--release", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--version", default="0.3.7")
    args = parser.parse_args()

    release = args.release.resolve()
    output = args.output.resolve()
    if not (release / "local_ai_chat.exe").is_file():
        raise SystemExit("Missing Windows release application")
    for pack in (
        "survival", "cooking", "coding", "electrical", "hunting", "first_aid"
    ):
        if not (release / "data/flutter_assets/assets/packs" / f"{pack}.json").is_file():
            raise SystemExit(f"Missing offline pack: {pack}")

    output.parent.mkdir(parents=True, exist_ok=True)
    root = f"LocalAIChat-Windows-v{args.version}-app-only"
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(release.rglob("*")):
            if path.is_file() and path.name != "test_chat.exe":
                archive.write(path, f"{root}/{path.relative_to(release).as_posix()}")
        archive.writestr(
            f"{root}/START_HERE.md",
            "Extract this upgrade over your existing Local AI Chat portable folder. "
            "Keep your models, speech, and media folders. This ZIP includes the "
            "application and six built-in Offline Library packs, but no model weights. "
            "Your chats are stored in your Windows user profile.\n",
        )

    with zipfile.ZipFile(output) as archive:
        bad = archive.testzip()
        if bad:
            raise SystemExit(f"ZIP validation failed: {bad}")
        print(f"Verified {output} ({len(archive.namelist())} files, {output.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
