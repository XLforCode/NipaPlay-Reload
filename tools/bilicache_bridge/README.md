# BiliCache Bridge 1.0 / protocol 1

Bridge source belongs to the NipaPlay fork. The browser extension remains a
separate repository. The host only pairs a configured cache root, opens its
current complete MP4, or reveals that MP4. It does not download media, run
scripts, accept executable paths from browser messages, or open an HTTP server.

## Install

1. In BilibiliDownload 1.7.0, select a cache root. Copy the extension ID shown in
   **播放器联动设置**. Keep the unpacked extension in a stable location; if its ID
   changes, reinstall this registration with the new ID.
2. Unpack the matching platform bridge release. Keep setup and host together.
3. Windows: run `install-windows.ps1`, or use the setup command below.
   macOS: open `install-macos.command`, or use the command below in Terminal.
   Select the **same root** and the actual fork player executable/application.
4. Click **配对播放器** in the extension. A two-minute one-use challenge proves
   both sides access the same directory. Copying a root marker is insufficient.
5. macOS: add the same root once using NipaPlay's media-library folder picker.
   This stores a security-scoped bookmark; permission must also work after a
   cold restart. The test package keeps the sandbox enabled.

```text
bilicache_setup install --extension-id <32-character-ID> --cache-root <directory> --player <NipaPlay.exe-or-NipaPlay.app>
bilicache_setup check
bilicache_setup uninstall
```

Windows executables have the `.exe` suffix. Setup uses the current user's
NativeMessagingHosts registry key. macOS uses Chrome's user NativeMessagingHosts
directory. Installed host/config live in `%LOCALAPPDATA%/BiliCacheBridge` or
`~/Library/Application Support/BiliCacheBridge`. Uninstall removes only bridge
registration/config/executable, never cached media or player settings.

macOS packages in this feature branch are **personal test builds, not notarized**.
Use the system's per-app first-open approval if required. Do not disable
Gatekeeper globally or remove the player sandbox. Signed public distribution
remains a separate release task.

## Build and verify

With the Dart SDK from the repository's Flutter toolchain:

```text
dart pub get
dart analyze
dart test
mkdir build
dart compile exe bin/bilicache_bridge.dart -o build/bilicache_bridge[.exe]
dart compile exe bin/setup.dart -o build/bilicache_setup[.exe]
```

Build each architecture on its native CI runner. No Dart runtime is needed by
users. The player and bridge use `packages/bilicache_protocol` for manifest and
path rules. Shared protocol fixtures must match the extension repository.

The `launch_requested` result means the OS accepted a startup request. It is not
proof of playback. Verify cold start, an already-running player, offline XML,
zero comments, seeking, Chinese paths, revocation and restart on both platforms.
