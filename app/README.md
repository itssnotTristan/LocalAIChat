# Local AI Chat

An offline Flutter chat app for Windows and iOS. The app stores chats and imported media on the device. Model and speech downloads are initiated by the user; chat and media analysis do not call a cloud inference service.

## Use

1. On Windows, open `local_ai_chat.exe` from the complete portable folder. Keep the EXE beside its `data` and DLL files.
2. Open **Models**. Use **Auto** when both the text model and vision model are present. Auto selects the text model for ordinary conversation and the vision model when media is attached.
3. Attach an image or video with **+**. Video import scans up to eight points per second and keeps up to the configured number of varied frames. Use **Add exact video moment** to add a frame automatic selection missed.
4. The microphone button records local speech; voice responses use local speech models when installed.

The small vision model can misinterpret scenes. Only selected frames are passed to it, and it does not listen to video audio. Check the selected frames before relying on a description. Past media frames are not resent on every follow-up. An error keeps the draft and attachments available for retry.

## Build from source

Flutter 3.47.5 is used for this project. From `app/`, run `flutter pub get`, `flutter test`, then `flutter build windows --release` on Windows. The iOS build runs in `.github/workflows/ios-unsigned.yml` on GitHub's macOS runner and produces an unsigned IPA. Signing and installing that IPA on a physical iPhone requires the device owner's Apple ID and a compatible sideloading method. The GitHub simulator image demonstrates the mobile layout; physical iPhone inference remains a separate acceptance test.

The repository does not contain model weights. The app can download the starter vision model, an optional open-ended text model, and local speech models in **Models** and **Settings**. The Windows portable package may include those weights alongside the executable.

## Current platforms

Windows is the primary tested runtime. iOS is built and checked on a macOS runner; physical device runtime is pending owner installation. Android work is deferred at the user's request.
