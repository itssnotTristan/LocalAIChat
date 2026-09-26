# Image Studio on iPhone

Open **Image Studio** from the chat drawer. Install the built-in Realistic Vision 5.1 Core ML model, or import a compatible Core ML ZIP from Files. Select an installed model in the model picker. You can rename or delete any installed image model; deleting the built-in copy returns the install button to its download state. The app checks an imported model by loading it on the iPhone before selecting it. Imported models must include compiled TextEncoder, UNet, VAE encoder and decoder, plus `vocab.json` and `merges.txt`.

Choose a photo, describe the edit, and tap **Make edit**. The original stays in place. **Save copy** exports a new PNG; **Use in chat** attaches it to the current conversation. **Stop** cancels a running edit. **Discard edit** removes only the edited result.

The built-in model is a separate photorealistic Core ML checkpoint, replacing the earlier base Stable Diffusion image model. The app does not add an NSFW safety checker to Image Studio, and ordinary edits of already nude adult photos are accepted. Clothing removal requests are unsupported. Results depend on the model and photo; a 512 × 512 result fits the whole input photo within a square.

Background changes use Apple's foreground-instance model to select the visible subject and put newly generated scenery behind it. If the app cannot select the whole subject confidently, it stops without saving a broken composite. Fine hair and edges can still be imperfect. Regular edits redraw the photo and can change details at higher strength.

The built-in archive comes from [Realistic Vision V5.1 6-bit Core ML](https://huggingface.co/darkmaniac7/TokForge-RealisticVision-5.1-CoreML-6bit) at a pinned revision and is checked with SHA-256 before installation. Its ZIP is about 875 MiB. Kira's proprietary image models cannot be bundled in an offline iPhone app.

The archive passed checksum and ZIP integrity checks on the development machine. The iOS CI build checks the native bridge. Actual image generation and the import flow still require a physical iPhone test after installing the IPA and model.
