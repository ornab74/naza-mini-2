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
- Crostini resize hardening uses a normal GTK window (no client-side header bar), XWayland by default, GTK non-GL mode, and no Linux rounded software clips. Set `NAZA_GDK_BACKEND=wayland` before `./run_linux.sh` only if your container's Wayland path is more stable.

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
./run_linux.sh
```

`run_linux.sh` is the recommended Crostini launcher. It enables Flutter
software rendering, disables GTK GL, and uses the resize-safe XWayland path.
To try the container's native Wayland path instead, run
`NAZA_GDK_BACKEND=wayland ./run_linux.sh`.

The first `flutter run` prepares the compatible local llama.cpp runtime before Flutter's native-assets step. Later builds reuse it.

Release build:

```bash
flutter build linux --release
./build/linux/x64/release/bundle/naza_llamadart_gui
```

## GitHub Actions builds

The workflow at `.github/workflows/build.yml` runs source analysis and builds
an Android App Bundle plus APK, Linux x64, Windows x64, macOS, and unsigned iOS artifacts. Linux
compiles the Crostini-compatible native bundle in the runner; the other targets
use LlamaDart's published native bundle for their platform. Missing Flutter host
directories are generated in CI, so platform scaffolding is not hand-edited in
the Linux development checkout.

### Android signing

Do not commit or paste a private signing key into this repository. For a normal
Android/Google Play release keystore, add these four **repository Actions
secrets** at GitHub: **Settings → Secrets and variables → Actions → New
repository secret**:

```text
ANDROID_KEYSTORE_BASE64   # base64 of the .jks or .keystore file
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
ANDROID_STORE_PASSWORD
```

The workflow decodes the keystore only inside the Android build runner, creates
the temporary `android/key.properties`, and signs the release APK. The files
are ignored locally and are not uploaded as source. If Play App Signing is
enabled, this should normally be the **upload key**, while Google keeps the
app-signing key. Google Play's quantum-ready certificates are public `.der`
files and are not an Android Gradle keystore; they cannot be substituted for
the `.jks` upload key.

### Advanced signing setup: Play + upload key + optional ML-DSA

The recommended production design has separate jobs and separate keys:

1. Enable **Google Play App Signing**. Google protects the Android app-signing
   key and signs the APKs delivered through Play. If Play Console shows
   **Quantum-ready (beta)**, Google also manages the hybrid post-quantum
   signing keys.
2. Generate and keep a separate Android **upload key**. GitHub Actions uses
   this key only to authenticate the release uploaded to Play.
3. Register the Google-managed certificate fingerprints with any API providers
   that authenticate your Android app.

When **Quantum-ready (beta)** is active, Google generates and protects a
hybrid classical-plus-post-quantum signing setup. Android 17 and newer can
verify the hybrid signature; older Android versions continue using the
classical signature blocks. You do not generate or upload the Google-managed
ML-DSA private key.

#### Generate the Android upload keystore

Run this locally on your Chromebook, from any directory. This deliberately
writes outside the project at `~/naza-secrets`, refuses to overwrite an
existing key, and generates both passwords with OpenSSL's operating-system
backed cryptographic random generator. Save the two displayed passwords in a
password manager before pressing Enter; they are never put in shell history or
on the `keytool` command line.

ML-DSA is a signature algorithm, not a password generator. It is not needed
here because Google Play manages the quantum-ready Play signing keys.

```bash
set -eu
umask 077
mkdir -m 700 -p "$HOME/naza-secrets"

if [ -e "$HOME/naza-secrets/naza-upload.jks" ]; then
  printf '%s\n' "Refusing to overwrite $HOME/naza-secrets/naza-upload.jks" >&2
  exit 1
fi

STORE_PASSWORD="$(openssl rand -hex 32)"
KEY_PASSWORD="$(openssl rand -hex 32)"
export STORE_PASSWORD KEY_PASSWORD

printf '\nSave these in your password manager now:\n'
printf 'ANDROID_STORE_PASSWORD: %s\n' "$STORE_PASSWORD"
printf 'ANDROID_KEY_PASSWORD:   %s\n\n' "$KEY_PASSWORD"
read -r -p 'Press Enter after saving them (Ctrl-C cancels): ' _

keytool -genkeypair -v \
  -keystore "$HOME/naza-secrets/naza-upload.jks" \
  -storetype JKS \
  -alias naza-upload \
  -keyalg RSA \
  -keysize 4096 \
  -sigalg SHA256withRSA \
  -validity 10950 \
  -dname "CN=NAZA Road Scanner, OU=Mobile, O=NAZA, C=US" \
  -storepass:env STORE_PASSWORD \
  -keypass:env KEY_PASSWORD

chmod 600 "$HOME/naza-secrets/naza-upload.jks"
unset STORE_PASSWORD KEY_PASSWORD
printf '\nCreated %s\n' "$HOME/naza-secrets/naza-upload.jks"
```

Keep the keystore in at least two encrypted offline backups. Never regenerate
this upload key after publishing unless you intentionally register a
replacement upload certificate in Play Console.

Check the keystore and export its public certificate:

```bash
keytool -list -v \
  -keystore "$HOME/naza-secrets/naza-upload.jks" \
  -alias naza-upload

keytool -exportcert -rfc \
  -keystore "$HOME/naza-secrets/naza-upload.jks" \
  -alias naza-upload \
  -file "$HOME/naza-secrets/naza-upload-cert.pem"
```

The certificate is public and can be registered in Play Console. The `.jks`
file and both passwords are private.

To inspect the key safely later, show metadata or the public certificate only;
do not print the private key:

```bash
stat -c '%A %U:%G %n' "$HOME/naza-secrets/naza-upload.jks"

keytool -list -v \
  -keystore "$HOME/naza-secrets/naza-upload.jks" \
  -alias naza-upload

keytool -exportcert -rfc \
  -keystore "$HOME/naza-secrets/naza-upload.jks" \
  -alias naza-upload |
  openssl x509 -noout -subject -issuer -fingerprint -sha256
```

`keytool` prompts for the keystore password. The expected file permissions are
`-rw-------` and the private file should remain under `~/naza-secrets`, never
under this repository.

#### GitHub Actions secrets for this repository

At **GitHub repository → Settings → Secrets and variables → Actions → New
repository secret**, add:

```text
ANDROID_KEYSTORE_BASE64   # base64 of naza-upload.jks
ANDROID_KEY_ALIAS         # naza-upload
ANDROID_KEY_PASSWORD      # private-key password
ANDROID_STORE_PASSWORD    # keystore password
```

Create the value for `ANDROID_KEYSTORE_BASE64` locally and paste it into the
secret field; do not commit the output. The terminal may visually wrap the
long value. If GitHub CLI is installed and authenticated, this avoids showing
the keystore contents at all:

```bash
base64 -w 0 "$HOME/naza-secrets/naza-upload.jks" |
  gh secret set ANDROID_KEYSTORE_BASE64
```

Alternatively, copy it directly to the Chromebook clipboard, paste it into
GitHub, and clear the clipboard immediately afterward:

```bash
base64 -w 0 "$HOME/naza-secrets/naza-upload.jks" |
  xclip -selection clipboard
# paste into GitHub, then clear it:
xclip -selection clipboard </dev/null
```

If `xclip` is not installed, use `sudo apt-get install -y xclip`. A wrapped
display is normal; valid Base64 contains only letters, numbers, `+`, `/`, and
`=`. Do not add spaces or manually retype the value.

The workflow consumes these names, decodes the keystore only on the Android
runner, and uses it to sign the upload App Bundle and APK. The key is removed
when the ephemeral runner is destroyed. The Android signing step is in
`.github/workflows/build.yml`.

#### Generate a separate ML-DSA key for app-level signatures

Do this only if you have a verifier in the app or on your server. It does not
replace the Android upload keystore. Use a current OpenSSL build that lists
ML-DSA; if the command is unavailable, your OpenSSL build needs an ML-DSA
provider or a supported cryptographic service.

```bash
openssl version
openssl list -public-key-algorithms | grep -i ML-DSA

umask 077
mkdir -m 700 -p "$HOME/naza-secrets/pqc"

openssl genpkey \
  -algorithm ML-DSA-65 \
  -out "$HOME/naza-secrets/pqc/naza-mldsa-65-private.pem"

openssl pkey \
  -in "$HOME/naza-secrets/pqc/naza-mldsa-65-private.pem" \
  -pubout \
  -out "$HOME/naza-secrets/pqc/naza-mldsa-65-public.pem"

chmod 600 "$HOME/naza-secrets/pqc/naza-mldsa-65-private.pem"
chmod 644 "$HOME/naza-secrets/pqc/naza-mldsa-65-public.pem"
```

The private ML-DSA key should preferably stay in an HSM/KMS or a dedicated
signing service. Do **not** add a `PQC_MLDSA_PRIVATE_KEY` secret to this
workflow yet: the current app does not consume one, and storing an unused
private key in CI only increases exposure. If a future signing service needs
the public key in CI, it can be committed as a public `.pem`/`.der` file or
provided as an optional secret such as:

```text
PQC_MLDSA_PUBLIC_KEY_BASE64
```

The `hybrid_pqc_cert.der`, `hybrid_classical_cert.der`, and
`deployment_cert.der` files shown in Play Console are public certificates
downloaded from Google Play. They are useful for fingerprint registration and
verification, but they contain no private signing material and must not be
placed in `ANDROID_KEYSTORE_BASE64`.

For Google Maps, OAuth, App Links, or another API that checks Android signing,
use the Google Play certificate fingerprints from **App signing**, not only the
upload-key fingerprint. With quantum-ready hybrid signing, an API provider may
need the fingerprints for the Google-managed classical and post-quantum
certificates, as well as the legacy classical certificate.

This setup gives Play a Google-managed quantum-ready Android signing chain
while keeping the replaceable upload key in GitHub Actions. An optional,
separate ML-DSA key can still be used for NAZA-owned scan data or server
signatures, but it is unrelated to Play App Signing.

#### Optional: isolated ML-DSA test container on DigitalOcean

This section is only for application-level ML-DSA experiments. It is not needed
to create the Android upload key; use the local procedure above for that. The
linked
`ornab74/roadscanner` example is a Python/liboqs application: its Dockerfile
builds `liboqs` and uses its Python bindings. That is useful for application
signatures, but it is not the same thing as installing an OpenSSL provider.

##### One-copy droplet bootstrap

After SSHing into the DigitalOcean droplet, paste this entire block once. It
installs Docker if needed, creates an isolated Debian 13 environment, and
creates the Android RSA upload keystore. The command asks for the Android
keystore passwords interactively. Google Play generates and manages the
quantum-ready ML-DSA signing keys, so this block does not create a replacement
ML-DSA Play key.

```bash
if ! command -v docker >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y docker.io
  sudo systemctl enable --now docker
fi

if command -v systemctl >/dev/null 2>&1 && ! docker info >/dev/null 2>&1; then
  sudo systemctl enable --now docker 2>/dev/null || true
fi

docker_cmd=(docker)
if ! docker info >/dev/null 2>&1; then
  docker_cmd=(sudo docker)
fi

"${docker_cmd[@]}" volume create naza-pqc-secrets >/dev/null
"${docker_cmd[@]}" run --rm -it \
  --name naza-pqc-openssl \
  --tmpfs /tmp:rw,noexec,nosuid,size=256m \
  -v naza-pqc-secrets:/secrets \
  debian:13-slim bash -lc '
    set -eu
    apt-get update
    apt-get install -y --no-install-recommends openssl ca-certificates default-jdk-headless
    rm -rf /var/lib/apt/lists/*

    umask 077

    keytool -genkeypair -v \
      -keystore /secrets/naza-upload.jks \
      -storetype JKS \
      -alias naza-upload \
      -keyalg RSA \
      -keysize 4096 \
      -sigalg SHA256withRSA \
      -validity 10950 \
      -dname "CN=NAZA Road Scanner, OU=Mobile, O=NAZA, C=US"

    chmod 600 /secrets/naza-upload.jks
    echo
    echo "Created keys in Docker volume: naza-pqc-secrets"
    echo "Android upload keystore: /secrets/naza-upload.jks"
    echo "Keep the private key and passwords secret."
  '
```

The Android keystore belongs in the four `ANDROID_*` GitHub Actions secrets
above. The Docker volume is persistent, so secure the droplet and do not run
`docker volume rm naza-pqc-secrets` unless you intentionally want to destroy
the upload key.

For an OpenSSL test, use a disposable Debian 13 container. Debian 13 Trixie
ships OpenSSL 3.5, which includes ML-DSA. The named Docker volume persists the
test files after the container exits; protect the droplet because Docker root
access can read that volume.

On the droplet host:

```bash
docker volume create naza-pqc-secrets
docker run --rm -it \
  --name naza-pqc-openssl \
  --tmpfs /tmp:rw,noexec,nosuid,size=256m \
  -v naza-pqc-secrets:/secrets \
  debian:13-slim bash
```

Inside the container:

```bash
apt-get update
apt-get install -y --no-install-recommends openssl ca-certificates
rm -rf /var/lib/apt/lists/*

openssl version
openssl list -providers
openssl list -public-key-algorithms | grep -i ML-DSA

umask 077
openssl genpkey \
  -algorithm ML-DSA-65 \
  -out /secrets/naza-mldsa-65-private.pem

openssl pkey \
  -in /secrets/naza-mldsa-65-private.pem \
  -pubout \
  -out /secrets/naza-mldsa-65-public.pem

chmod 600 /secrets/naza-mldsa-65-private.pem
chmod 644 /secrets/naza-mldsa-65-public.pem
```

This is for application-level signing or verification experiments. It does
not make an ML-DSA Android APK signer. Keep the private ML-DSA key in a KMS,
HSM, or other dedicated signing service for production. Do not copy it into
the Flutter app or add it to GitHub Actions unless a signing service has been
implemented to use it.

The same container can create the Android upload keystore, but that keystore
still needs a standard Android-compatible key such as RSA:

```bash
apt-get update && apt-get install -y --no-install-recommends default-jdk-headless
umask 077
keytool -genkeypair -v \
  -keystore /secrets/naza-upload.jks \
  -storetype JKS \
  -alias naza-upload \
  -keyalg RSA \
  -keysize 4096 \
  -sigalg SHA256withRSA \
  -validity 10950 \
  -dname "CN=NAZA Road Scanner, OU=Mobile, O=NAZA, C=US"
```

Use the Android `.jks` plus its two passwords for the four `ANDROID_*`
GitHub Actions secrets described above. Never put the ML-DSA PEM private key
in `ANDROID_KEYSTORE_BASE64`.

#### Install an ML-DSA-capable OpenSSL on Debian 12/Crostini

Debian 12 Bookworm ships OpenSSL 3.0, which does not include the ML-DSA
algorithms. Do not replace `/usr/bin/openssl`, because the system and other
packages depend on it. Install OpenSSL 3.5 LTS beside it in your user
directory. OpenSSL 3.5 added ML-KEM, ML-DSA, and SLH-DSA support and is listed
as an LTS branch by the OpenSSL project.

```bash
sudo apt update
sudo apt install -y build-essential perl zlib1g-dev ca-certificates curl

cd /tmp
curl -fLO https://github.com/openssl/openssl/releases/download/openssl-3.5.8/openssl-3.5.8.tar.gz
curl -fLO https://github.com/openssl/openssl/releases/download/openssl-3.5.8/openssl-3.5.8.tar.gz.sha256
sha256sum -c openssl-3.5.8.tar.gz.sha256
tar -xzf openssl-3.5.8.tar.gz
cd openssl-3.5.8

./Configure \
  --prefix="$HOME/.local/openssl-3.5.8" \
  --openssldir="$HOME/.local/openssl-3.5.8/ssl" \
  --libdir=lib \
  shared zlib
make -j2
make install_sw
```

Use the new copy for ML-DSA commands without changing the system default:

```bash
export OPENSSL_PREFIX="$HOME/.local/openssl-3.5.8"
export PATH="$OPENSSL_PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$OPENSSL_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export OPENSSL_MODULES="$OPENSSL_PREFIX/lib/ossl-modules"

openssl version
openssl list -public-key-algorithms | grep -i ML-DSA
```

The final command should show ML-DSA algorithms. These environment exports
apply to the current terminal. The existing ML-DSA generation commands can
then be run in that same terminal. The official OpenSSL downloads page
contains the release signature and checksum links; verify those when choosing
a newer patch release.

Alternatively, a new Debian 13 (Trixie) container provides an OpenSSL 3.5
package. Avoid changing a working Bookworm container's APT sources in place
unless you have a complete Crostini backup.

## Manual native-runtime repair

Normally unnecessary. To intentionally rebuild the compatibility bundle:

```bash
rm -rf native-bundles/linux-x64 third_party/llamadart-native-b10075
./tool/prepare_linux_llamadart_native.sh
flutter clean
flutter pub get
./run_linux.sh
```


## Restored inference behavior (v0.2.2)

The road scanner model run uses 2048 context, 4 llama.cpp CPU threads, 256/128 batch sizing, 64-token CHUNKD pieces up to 256 total tokens, and a 128-token direct mode. Raw completion text remains visible in the result panel.
