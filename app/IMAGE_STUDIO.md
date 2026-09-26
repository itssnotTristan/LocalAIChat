# Image Studio

Open **Image Studio** from the chat drawer. Tap **Install image model** once on each device, choose a photo, describe the desired edit, and tap **Make edit**. The original stays in place. **Save copy** exports a new PNG; **Use in chat** attaches that PNG to the current conversation. **Stop** cancels a running edit.

All inference and files stay on the device. Windows uses `stable-diffusion.cpp` with Stable Diffusion 1.5; the installer downloads the NVIDIA CUDA runtime only if an NVIDIA GPU is present. iOS uses Apple's Swift Stable Diffusion pipeline and its 6-bit Core ML model. The Windows checkpoint is roughly 4 GiB and the iPhone model is roughly 1.5 GiB. The editor makes a 512 × 512 result and fits the entire source photo within the square.

On iPhone, a request to change the background uses Apple's person segmentation to keep the original person, generates empty scenery, and composites the two. If it cannot find a person, the edit stops and keeps the original. Fine hair and edges can still be imperfect. Windows background replacement stops with an explanation until it has an equivalent person mask; its regular image-to-image mode redraws the entire image and may change faces or poses. Redraw amount defaults to 30% for regular edits. Clothing removal requests stop with an explanation instead of showing a damaged image. **Discard edit** removes an unwanted app-owned result; the original is kept.

Models and runtimes are downloaded from their publishers with pinned SHA-256 checksums:

- Windows runtime: https://github.com/leejet/stable-diffusion.cpp
- Windows checkpoint: https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-v1-5
- iPhone Core ML checkpoint: https://huggingface.co/apple/coreml-stable-diffusion-v1-5-palettized
- CUDA runtime libraries: https://developer.download.nvidia.com/compute/cuda/redist/
- Model license and use conditions: https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-v1-5

Validation: a non-sensitive photo edit ran locally on the RTX 4060 in the earlier whole-image editor. Dart tests and the Windows build cover app integration, and the iOS CI build checks that the native bridge compiles. Person segmentation and image generation together still need a physical iPhone test after installing the unsigned IPA and downloading its model.
