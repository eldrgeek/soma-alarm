# Pulse / Sidekick — Release & Install Workflow

`release.sh` is the canonical way to ship a new build to the Pixel. Two install paths:

| Path        | When                                  | How it lands                                                  |
|-------------|----------------------------------------|---------------------------------------------------------------|
| `push-local`| Pixel + Mac on home wifi               | Wireless adb install. Auto-discovers Pixel via mDNS.          |
| `push-vps`  | Anywhere else (different network/LTE)  | scp to VPS → Pixel browser opens `https://…/pulse/latest.apk` |

## Prerequisites

- **Flutter + Android toolchain** (`flutter doctor` clean enough to `flutter build apk`).
- **adb** in `PATH` (`brew install --cask android-platform-tools`).
- **qrencode** (`brew install qrencode`) — only needed once, to regenerate the QR PNG.
- **VPS auth.** Either an SSH key in `~/.ssh/authorized_keys` for `dev@vpsmikewolf.duckdns.org`, or set `VPS_PASSWORD` in the environment so the script falls back to `sshpass` (already on this machine).
- **Java.** If `flutter build apk` complains about missing JRE, point it at the Homebrew JDK:
  `export JAVA_HOME=/opt/homebrew/opt/openjdk@21 && export PATH="$JAVA_HOME/bin:$PATH"`.
- **Android SDK NDK.** First-time Android builds may need `sdkmanager --licenses` accepted via Android Studio.

## Subcommands

```
./release.sh build               # flutter build apk --release
./release.sh build --debug       # flutter build apk --debug
./release.sh push-local          # build + adb wireless install on Pixel
./release.sh push-vps            # build + scp to VPS
./release.sh push-all            # both
./release.sh status              # report local APK / Pixel installed / VPS file / QR
```

Global flags:
- `--debug` — build the debug variant instead of release.
- `--force` — rebuild even if no source changed; regenerate QR even if present.

The script skips `flutter build` if the existing APK is newer than everything in `lib/` and `pubspec.yaml`. Use `--force` to bypass.

## VPS layout (one-time, already done)

- `/var/www/pulse/` is owned by `dev:dev`. The script writes `latest.apk` and a versioned copy `sidekick-<version>.apk`.
- nginx config in `/etc/nginx/sites-enabled/wolfchat` has a `location /pulse/` block that aliases to `/var/www/pulse/`, sets MIME `application/vnd.android.package-archive`, and adds `Content-Disposition: attachment` so Chrome/Chromium downloads instead of trying to render.
- TLS via the existing Let's Encrypt cert. URL: `https://vpsmikewolf.duckdns.org/pulse/latest.apk`.

## QR code for the Pixel

`release/pulse-install-qr.png` encodes the VPS URL. Mike's Pixel camera scans it → Chrome opens → tap → install. Bookmark the URL for one-tap reinstall later.

The PNG is regenerated only on `--force` or when missing — the URL is meant to be permanent.

## Troubleshooting

| Symptom                                              | Fix                                                                                  |
|------------------------------------------------------|---------------------------------------------------------------------------------------|
| `no Pixel found via mDNS` and adb connect fails      | Plug Pixel in via USB, or re-pair wireless adb (Settings → Developer options → Wireless debugging → Pair using pairing code). The script auto-falls-back to USB. |
| `SSH to dev@vpsmikewolf.duckdns.org failed`          | Check VPN, DNS, and that the VPS is up. Easiest sanity: `curl -sI https://vpsmikewolf.duckdns.org/pulse/latest.apk`. If the URL responds, SSH key is the issue — ensure `~/.ssh/id_ed25519_vps` is present (VPS password retired from files 2026-06-10; emergency copy in Mike's password manager). |
| Pixel not on home wifi (LTE/coffee shop)             | Use `push-vps`, then scan the QR.                                                     |
| `Unable to locate a Java Runtime`                    | `export JAVA_HOME=/opt/homebrew/opt/openjdk@21 && export PATH="$JAVA_HOME/bin:$PATH"`. |
| `LicenceNotAcceptedException` for NDK                | Open Android Studio → SDK Manager → accept NDK license; or `yes \| sdkmanager --licenses`. |
| `qrencode not installed`                             | `brew install qrencode`.                                                              |
| Browser on Pixel renders APK as text instead of installing | Clear cache; ensure response includes `Content-Type: application/vnd.android.package-archive` (the script's nginx config sets this). |

## Internals (curious-future-Mike notes)

- mDNS parser pulls the first `ip:port` matching `_adb-tls-connect._tcp` from `adb mdns services`. If empty it falls back to `PIXEL_FALLBACK_IP=192.168.4.27:5555` (last-known DHCP lease as of 2026-05-05). Update the constant if DHCP rotates the Pixel for good.
- VPS path is hardcoded to `/var/www/pulse/`; change `VPS_DEST_DIR` and `VPS_URL` in the script if you move it.
- `apk_version` prefers `aapt`; if missing it reads `pubspec.yaml` and tags the version `0.1.0~pubspec` so you know it's a fallback.
