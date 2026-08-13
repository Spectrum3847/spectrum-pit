# Spectrum Pit

FRC pit logistics for Spectrum 3847. One app that keeps the team running at an event:

- **Inventory**: every tool and part, where it lives in the lab or the pit, with a map of both so nothing goes missing.
- **Event packing**: the four-stage packing workflow (Packing, Staging, Loading, Ready); each item may have one optional packing photo.
- **Borrowed tools**: track what left the pit with whom, and what came back.

Built with Flutter for iOS, Android, and desktop (Windows, macOS, Linux).

## Install

Builds are attached to [this repo's releases](https://github.com/Spectrum3847/spectrum-pit/releases). They are unsigned, so each platform needs a step or two.

### Check the download first

Every artifact ships with a `.sha256` file next to it. Because these builds are unsigned, the instructions below ask you to click past your platform's own integrity check. A colocated `.sha256` only detects a corrupted download: it comes from the same release, so an attacker who replaces both the artifact and its checksum supplies a matching sum. Detecting tampering needs the expected checksum from a separate trusted channel, or a signed artifact. Download both files into the same folder and run:

```bash
sha256sum -c App-Name.zip.sha256      # Linux, and Git Bash on Windows
shasum -a 256 -c App-Name.zip.sha256  # macOS
```

```powershell
# Windows PowerShell, if you would rather not install anything
(Get-FileHash App-Name.zip -Algorithm SHA256).Hash -eq `
  ((Get-Content App-Name.zip.sha256) -split '\s+')[0].ToUpper()
```

`OK` (or `True`) means the file is intact. Anything else means download it again, and do not run it.

### iOS (AltStore, SideStore, LiveContainer)

Open Sources, add a source, and paste one of these URLs:

- Stable: `https://spectrumpit-stable.web.app/stable.json`
- Nightly: `https://spectrumpit-nightly.web.app/nightly.json`

Spectrum Pit then shows up as an app you can install, and later builds arrive as updates. The installer re-signs the IPA on device with a free Apple ID, so no paid developer account is needed. Free signing expires after 7 days, so let AltStore or SideStore refresh weekly. SideStore can refresh on device, without a computer.

The stable source tracks releases; the nightly source rebuilds every night from the latest source.

### Android

Download the APK from a release and install it. Android will ask you to allow installs from this source the first time.

### Desktop

Each release carries a Linux AppImage, a Windows ZIP, and a zipped macOS `.app`. None are code-signed:

- Linux: `chmod +x` the AppImage and run it.
- Windows: unzip, then choose "More info" then "Run anyway" at the SmartScreen prompt.
- macOS: unzip, then right-click the app and choose Open, since Gatekeeper blocks a double-click on an unsigned app.

## About this repository

This is the public mirror of Spectrum Pit. The team develops in a private repository; each published release is synced here as a single squashed commit, so this repo always holds the source of the latest release without internal history.

## Contributing

Pull requests are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md).

## Maintainer

This project is maintained by [@Project516](https://github.com/Project516) ([project516.dev](https://project516.dev)).

## License

[AGPL-3.0](LICENSE). If you distribute a modified version of this app, or run one as a service for others, you must make its source available under the same license.
