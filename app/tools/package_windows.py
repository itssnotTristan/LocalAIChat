"""Build the portable Windows release ZIP from a verified local build and weights."""

from __future__ import annotations

import argparse
import hashlib
import sys
import zipfile
from pathlib import Path


MODEL_FILES = {
    "smolvlm2-500m/SmolVLM2-500M-Video-Instruct-Q8_0.gguf": "6f67b8036b2469fcd71728702720c6b51aebd759b78137a8120733b4d66438bc",
    "smolvlm2-500m/mmproj-SmolVLM2-500M-Video-Instruct-Q8_0.gguf": "921dc7e259f308e5b027111fa185efcbf33db13f6e35749ddf7f5cdb60ef520b",
    "qwen25-1.5b-abliterated/Qwen2.5-1.5B-Instruct-abliterated.Q4_K_M.gguf": "59aa9f44bde5349dbe292d7024d197db605f422b8baf65f3246a59abbde4e8e9",
    "qwen35-4b-uncensored/Qwen3.5-4B-Uncensored.Q4_K_M.gguf": "f3a2e8f1837f52247a5b7b28f379923c98cc38fa8b339a943ba49b518be8b562",
    "qwen35-4b-uncensored/Qwen3.5-4B-Uncensored.mmproj-Q8_0.gguf": "04a3af332afa255093f04b1a95ae1065637c140b8b365f721f0be89b62ae2d16",
    "qwen3-4b-nymphaea-rp/Qwen3-4B-Nymphaea-RP.Q4_K_M.gguf": "7896e1c1e498554887ea6439c44939216f67146fa3c3298ee7a95c2cf206376d",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--release", type=Path, required=True)
    parser.add_argument("--models", type=Path, required=True)
    parser.add_argument("--speech", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--version", default="0.3.0")
    args = parser.parse_args()

    release = args.release.resolve()
    models = args.models.resolve()
    speech = args.speech.resolve()
    output = args.output.resolve()
    if not (release / "local_ai_chat.exe").is_file():
        raise SystemExit("Windows release EXE is missing")
    for rel, expected in MODEL_FILES.items():
        path = models / rel
        if not path.is_file() or sha256(path) != expected:
            raise SystemExit(f"Model missing or checksum mismatch: {path}")
        print(f"Verified {rel}", flush=True)
    for rel in [
        "sherpa-onnx-moonshine-tiny-en-int8/preprocess.onnx",
        "sherpa-onnx-moonshine-tiny-en-int8/encode.int8.onnx",
        "sherpa-onnx-moonshine-tiny-en-int8/uncached_decode.int8.onnx",
        "sherpa-onnx-moonshine-tiny-en-int8/cached_decode.int8.onnx",
        "sherpa-onnx-moonshine-tiny-en-int8/tokens.txt",
        "kokoro-en-v0_19/model.onnx",
        "kokoro-en-v0_19/voices.bin",
        "kokoro-en-v0_19/tokens.txt",
    ]:
        if not (speech / rel).is_file():
            raise SystemExit(f"Speech file missing: {rel}")
    if not (speech / "kokoro-en-v0_19/espeak-ng-data").is_dir():
        raise SystemExit("Kokoro phoneme data is missing")

    root = f"LocalAIChat-Windows-v{args.version}"
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", allowZip64=True) as archive:
        def add(path: Path, relative: str) -> None:
            compression = zipfile.ZIP_STORED if path.suffix.lower() in {".gguf", ".onnx", ".bin"} else zipfile.ZIP_DEFLATED
            archive.write(path, f"{root}/{relative.replace(chr(92), '/')}", compress_type=compression, compresslevel=6 if compression == zipfile.ZIP_DEFLATED else None)

        for path in sorted(release.rglob("*")):
            if path.is_file() and path.name != "test_chat.exe":
                add(path, path.relative_to(release).as_posix())
        for rel in MODEL_FILES:
            add(models / rel, f"models/{rel}")
        for folder in ["sherpa-onnx-moonshine-tiny-en-int8", "kokoro-en-v0_19"]:
            for path in sorted((speech / folder).rglob("*")):
                if path.is_file():
                    add(path, f"speech/{folder}/{path.relative_to(speech / folder).as_posix()}")

        archive.writestr(f"{root}/START_HERE.md", f"""# Local AI Chat v{args.version} for Windows

Extract this ZIP, then run local_ai_chat.exe. Keep the extracted data, models, speech, EXE, and DLL files together.

The app includes local vision, text, adult roleplay, transcription, and five offline voices. Use Models to pick a model. In the conversation menu, choose a personality and edit saved memory. The phone icon starts a voice call. Fish Audio is optional and online: configure it in Settings > Voice only if you want it.

If you used an older portable ZIP, installing this new folder will retain the chats in your Windows user profile. The app remaps bundled model and speech paths when the old folder is gone.
""")
        archive.writestr(f"{root}/MODEL_SOURCES.txt", """Model sources:
https://huggingface.co/ggml-org/SmolVLM2-500M-Video-Instruct-GGUF
https://huggingface.co/mradermacher/Qwen2.5-1.5B-Instruct-abliterated-GGUF
https://huggingface.co/mradermacher/Qwen3.5-4B-Uncensored-GGUF
https://huggingface.co/mradermacher/Qwen3-4B-Nymphaea-RP-GGUF
https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models
https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models
""")
    with zipfile.ZipFile(output) as archive:
        bad = archive.testzip()
        if bad:
            raise SystemExit(f"ZIP check failed: {bad}")
        print(f"ZIP verified: {output} ({len(archive.namelist())} entries, {output.stat().st_size} bytes)", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
