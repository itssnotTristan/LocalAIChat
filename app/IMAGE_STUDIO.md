# Image Studio

Open **Image Studio** from the chat drawer. Tap **Install image model** once on each device, choose a photo, describe the desired edit, and tap **Make edit**. The original stays in place. **Save copy** exports a new PNG; **Use in chat** attaches that PNG to the current conversation. **Stop** cancels a running edit.

All inference and files stay on the device. Windows uses `stable-diffusion.cpp` with Stable Diffusion 1.5; the installer downloads the NVIDIA CUDA runtime only if an NVIDIA GPU is present. iOS uses Apple's Swift Stable Diffusion pipeline and its 6-bit Core ML model. The Windows checkpoint is roughly 4 GiB and the iPhone model is roughly 1.5 GiB. The editor makes a 512 × 512 result and fits the entire source photo within the square. Some prompts may need a higher change strength to become visible. This is a general photo editor; there is no clothing removal control.

Models and runtimes are downloaded from their publishers with pinned SHA-256 checksums:

- Windows runtime: https://github.com/leejet/stable-diffusion.cpp
- Windows checkpoint: https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-v1-5
- iPhone Core ML checkpoint: https://huggingface.co/apple/coreml-stable-diffusion-v1-5-palettized
- CUDA runtime libraries: https://developer.download.nvidia.com/compute/cuda/redist/
- Model license and use conditions: https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-v1-5

Validation: a non-sensitive photo edit ran locally on the RTX 4060, producing a saved PNG. Dart tests and the Windows build cover the app integration. Physical iPhone inference requires device validation after installing the unsigned IPA and downloading its model.
