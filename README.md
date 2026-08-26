# IMPORTANT: use the real NAZA launcher

On Linux, run:

```bash
chmod +x run_linux.sh
./run_linux.sh
```

The launcher checks that `lib/main.dart` points to `NazaShell`, that the CHUNKD scanner modes exist, and that the raw **Model output** panel exists before starting Flutter. Do **not** run `flutter create .` inside this directory; that would replace the application source with Flutter's demo template.

# NAZA Road Scanner — LlamaDart / Llama 3 Small

Scanner-only Flutter GUI port of NAZA. This build contains **no chat UI**, **no Gemma / LiteRT-LM runtime**, and the scanner generation choices: **CHUNKD**, **CHUNKD only**, and **direct single-call**.

## Startup flow

On the first launch, NAZA automatically downloads the pinned model, verifies
its SHA-256, encrypts it, removes the plaintext copy, and loads the Road
Scanner. This first-boot setup runs once per device. On later launches, NAZA
decrypts the protected model into a temporary runtime file and opens the Road
Scanner automatically.

When the scanner is ready, enter the road or destination you are traveling to,
choose **CHUNKD**, and tap **Scan**. Always confirm the result against current
on-site conditions; the scanner is decision support, not a replacement for
direct inspection.

The app opens on **Scan** after startup. The bottom navigation has only three
pages: **Scan**, **History**, and **Settings**. History is private by default:
results are not written to encrypted History unless you turn on **Save scans to
History** in Settings or press **Save to History** on a result. The result screen
always gives you a clear **Scan again** path for the next trip.

## Model trust pin

- Model: `llama3-small-Q3_K_M.gguf`
- Exact size: `111454016` bytes
- SHA-256: `8e4f4856fb84bafb895f1eb08e6c03e4be613ead2d942f91561aeac742a619aa`
- LlamaDart: `0.8.17`
- llama.cpp native ABI: `b10075`
- Linux inference: CPU (`gpuLayers: 0`, `GpuBackend.cpu`)

Built-in mirrors:

1. GitHub Release: `ornab74/naza_one_generation_ui_code` release `v1`
2. Hugging Face: `tensorblock/llama3-small-GGUF`
3. Pinata/IPFS: `silver-southern-echidna-758.mypinata.cloud/ipfs/bafybeifb3732qilucogsp7d3q4kgqewkyu2lguyhndgzv5jlbkqiptqt5a` (built in; may be overridden in Model Manager)

## Secure adaptive multi-host downloader

The model manager uses a resumable, concurrent range downloader instead of a single HTTP stream.

- Probes every configured provider concurrently with HTTPS range requests.
- Uses 4 MiB chunks and concurrent provider workers.
- Keeps one worker active per healthy provider while adaptive workers follow the fastest EWMA throughput score.
- Automatically fails chunks over to another provider on timeout, truncation, bad range metadata, or provider cooldown.
- Supports interrupted-download resume with per-chunk SHA-256 fingerprints.
- Re-hashes every resumed chunk before trusting it.
- Requires exact `Content-Range` and expected total file size.
- Refuses HTTP downgrade redirects and redirects outside the provider trust domain.
- Uses the platform TLS certificate verifier; there is no certificate-bypass path.
- Reassembles chunks in strict byte order, verifies the exact 111,454,016-byte size, then verifies the pinned whole-file SHA-256.
- Only after full verification is the model atomically promoted.
- The controller immediately encrypts the verified model using the existing chunked AES-256-GCM container and removes plaintext at rest.

The built-in Pinata mirror is enabled by default and may be overridden in Model Manager. Clearing the field resets it to the built-in mirror. A replacement Pinata mirror may be entered as an HTTPS `*.mypinata.cloud` / `*.pinata.cloud` gateway URL, an `ipfs://CID` URI, or a bare CID. If Pinata is not configured, GitHub and Hugging Face still race concurrently.

## Mobile UI / jank changes

- Mobile top bar no longer renders the large status-pill wall.
- Section subtitles are hidden on compact layouts to recover vertical space.
- Live `BackdropFilter` blur is removed entirely and desktop shadows are reduced; static glass tint keeps the look without repeated offscreen blur passes.
- Linux/mobile gradient-icon shaders are replaced with a solid accent icon to reduce raster work.
- Download/decrypt/encrypt progress notifications are coalesced to at most ~10 UI updates/second instead of rebuilding the whole shell for every progress event.
- AES model encryption/decryption uses a native Linux OpenSSL fast path and the native `cryptography_flutter` AES-GCM implementation on Android/iOS/macOS, with 16 MiB work quanta and compatibility with older encrypted files.
- The Settings page contains the model repair tools, key rotation, advanced checks, privacy control, and a long plain-language **Safety Tips** driving manual.
- CPU inference keeps two logical cores free when possible and uses smaller batch/micro-batch sizes to avoid starving Flutter rendering.
- Leaving the scanner paints the destination page before background model re-encryption begins, eliminating the apparent post-scan freeze.
- Scanner controls use a responsive card with CHUNKD as the default mode.
- Result metadata wraps safely and long defense/colorwheel strings no longer force horizontal layout.
- Raw model output is preserved and displayed exactly as generated; classification is derived separately from that raw output.

## Performance verification

For meaningful DevTools frame timing, use profile mode rather than debug mode:

```bash
flutter run --profile -d linux
```

Debug builds include assertion/JIT/debugger overhead and can report janky frames that do not reproduce in profile/release builds.

## Debian 12 / ChromeOS Crostini fix

The upstream precompiled `b10075` Linux runtime can require GLIBC symbols newer than Debian 12 provides. This project points LlamaDart at a local native bundle under `native-bundles/`.

**You do not need to run a separate bootstrap first.** The included `linux/CMakeLists.txt` calls `tool/prepare_linux_llamadart_native.sh` during the first Linux CMake configure. That script compiles the exact `b10075` bridge on your Linux host with optional GPU/BLAS backends disabled, so the resulting libraries link against the host GLIBC. It also stages canonical `.so` files plus the required ELF SONAME aliases for versioned outputs such as `libllama.so.0.0.0`.

## Linux build

```bash
sudo apt update
sudo apt install -y clang cmake ninja-build pkg-config libgtk-3-dev build-essential git binutils

flutter clean
flutter pub get
flutter run -d linux
```

The first `flutter run` prepares the compatible local llama.cpp runtime before Flutter's native-assets step. Later builds reuse it.

Release build:

```bash
flutter build linux --release
./build/linux/x64/release/bundle/naza_llamadart_gui
```

## GitHub Actions builds

The workflow at `.github/workflows/build.yml` runs source analysis and builds
Android APK, Linux x64, Windows x64, macOS, and unsigned iOS artifacts. Linux
compiles the Crostini-compatible native bundle in the runner; the other targets
use LlamaDart's published native bundle for their platform. Missing Flutter host
directories are generated in CI, so platform scaffolding is not hand-edited in
the Linux development checkout.

## Manual native-runtime repair

Normally unnecessary. To intentionally rebuild the compatibility bundle:

```bash
rm -rf native-bundles/linux-x64 third_party/llamadart-native-b10075
./tool/prepare_linux_llamadart_native.sh
flutter clean
flutter pub get
flutter run -d linux
```


## Restored inference behavior (v0.2.2)

The road scanner model run uses 2048 context, 4 llama.cpp CPU threads, 256/128 batch sizing, 64-token CHUNKD pieces up to 256 total tokens, and a 128-token direct mode. Raw completion text remains visible in the result panel.
