# Installing Ankountant

Ankountant ships two clients: a **macOS desktop app** you download and run, and
a native **iOS app** you build and sign yourself with Xcode. Neither is
distributed through the App Store or notarized by Apple, so each needs one extra
step to get past the OS security prompt — those steps are spelled out below.

---

## A. Desktop (macOS)

### 1. Download

Grab the latest build from the
[**Releases** page](https://github.com/ericrcwu001/ankountant/releases) and pick
the `.dmg` for your Mac:

| Mac                   | File                                 |
| --------------------- | ------------------------------------ |
| Apple Silicon (M1–M4) | `ankountant-<version>-mac-apple.dmg` |
| Intel                 | `ankountant-<version>-mac-intel.dmg` |

> Not sure which Mac you have? Apple menu → **About This Mac**. A "Chip" line
> (e.g. Apple M2) means Apple Silicon; a "Processor" line (e.g. Intel Core i7)
> means Intel.

### 2. Install on macOS

1. Double-click the `.dmg` to mount it, then drag **Ankountant** into your
   **Applications** folder.
2. Eject the mounted disk and delete the `.dmg` if you like.

On macOS 15 Sequoia / macOS 26 and later the `.dmg` itself may be blocked before
it even mounts, with _"Apple could not verify 'ankountant-…-mac-apple.dmg' is
free of malware that may harm your Mac…"_ offering only **Move to Trash** /
**Done**. Don't trash it — this is Gatekeeper, the same check covered in step 3.
Click **Done**, then either approve it under **System Settings → Privacy &
Security → Open Anyway**, or strip the download flag in Terminal and reopen the
`.dmg`:

```bash
xattr -dr com.apple.quarantine ~/Downloads/ankountant-*-mac-*.dmg
```

Removing the flag from the `.dmg` before mounting also de-quarantines the app you
copy out of it, so it launches without another prompt in step 3.

### 3. First launch on macOS — getting past Gatekeeper

These builds are **not signed or notarized by Apple** (that requires a paid
Apple Developer account), so the first time you open the app macOS will refuse
with a message like _"Ankountant" can't be opened because Apple cannot check it
for malicious software_ or _"Ankountant" is damaged_. This is Gatekeeper, not a
virus — you just have to approve the app once. Use whichever method your macOS
version offers:

- **Right-click → Open** (older macOS): in **Applications**, right-click (or
  Control-click) **Ankountant** → **Open** → **Open** again in the dialog.
- **System Settings** (macOS 15 Sequoia / macOS 26 and later): double-click the
  app once (it gets blocked), then go to **System Settings → Privacy &
  Security**, scroll down to _"Ankountant was blocked…"_ and click **Open
  Anyway**, then confirm.
- **Terminal** (always works): remove the quarantine flag, then open normally:

```bash
xattr -dr com.apple.quarantine /Applications/Ankountant.app
```

You only need to do this once. After that, Ankountant opens like any other app.

---

## B. iOS (build & run on your iPhone with Xcode)

Ankountant for iOS isn't on the App Store, so you compile it from source and
sign it with **your own Apple ID / development team**. You need a **Mac**.

> Prefer not to build? Tagged iOS releases also attach a prebuilt
> **unsigned `.ipa`** you can sideload with [AltStore](https://altstore.io/) or
> [Sideloadly](https://sideloadly.io/) using your own Apple ID. The Xcode route
> below gives you the full build and is what this section covers.

### 1. Prerequisites

- **Xcode** (a recent release; the project targets **iOS 18+**, Swift 6). Open
  it once and install the iOS platform components.
- **Rust** with the iOS targets, plus the protobuf and project-generator tools.
  See `ios/README.md` for the authoritative version table.

```bash
# Rust + iOS targets
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios

# Build tools (Homebrew)
brew install protobuf swift-protobuf xcodegen
```

### 2. Clone and generate the project

```bash
git clone --recursive https://github.com/ericrcwu001/ankountant.git
cd ankountant/ios

./scripts/build-xcframework.sh   # compiles the Rust core into AnkiRust.xcframework (slow the first time)
./scripts/generate-protos.sh     # generates the Swift protobuf types

cd AnkountantApp && xcodegen generate && cd ..
open AnkountantApp/AnkountantApp.xcodeproj
```

### 3. Sign with your development team

In Xcode:

1. **Xcode → Settings → Accounts → +** and sign in with your Apple ID.
2. In the Project navigator select the **AnkountantApp** project, then the
   **AnkountantApp** target → **Signing & Capabilities** tab.
3. Tick **Automatically manage signing** and set **Team** to your Apple ID /
   team.
4. Change the **Bundle Identifier** to something unique to you — the default
   `com.ankountant.ios` is already claimed, and Apple requires globally-unique
   IDs. Use e.g. `com.<yourname>.ankountant`.
5. Repeat for the **AnkountantWidget** target (home-screen widget): same Team,
   and give it a matching unique ID such as `com.<yourname>.ankountant.widget`.

> **App Groups note:** the app and its widget share data through an App Group
> (`group.com.ankountantapp`). App Groups require a **paid Apple Developer
> Program** membership. If you only have a **free** Apple ID, either:
>
> - remove the **AnkountantWidget** target and delete the _App Groups_
>   capability from both targets' _Signing & Capabilities_, **or**
> - just run in the **iOS Simulator** (below), which needs no signing at all.

### 4. Run on your iPhone

1. Connect your iPhone (iOS 18+) over USB and **Trust** the computer.
2. Pick your iPhone from the run-destination menu at the top of Xcode.
3. Press **▶ Run** (`Cmd + R`) to build, install, and launch.
4. The first launch is blocked as an _Untrusted Developer_. On the phone go to
   **Settings → General → VPN & Device Management**, tap your developer profile,
   and choose **Trust**. Relaunch the app.

### 5. How long the install lasts

| Account type                          | App validity | Notes                                                 |
| ------------------------------------- | ------------ | ----------------------------------------------------- |
| Free Apple ID                         | **7 days**   | Re-run from Xcode to renew; max 3 apps; no App Groups |
| Paid Apple Developer Program ($99/yr) | **1 year**   | Full capabilities incl. App Groups                    |

### 6. Just want to try it? Use the Simulator

No Apple account or signing required:

```bash
# after step 2 above
open AnkountantApp/AnkountantApp.xcodeproj
```

Select an **iOS Simulator** (e.g. iPhone 17 Pro) as the destination and press
**Run**.

---

## License

Ankountant is distributed under the **AGPL-3.0** license and includes the
[ankitects/anki](https://github.com/ankitects/anki) Rust backend (also
AGPL-3.0). See [LICENSE](./LICENSE).
