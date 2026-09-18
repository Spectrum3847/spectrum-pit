# Spectrum Pit

FRC pit logistics for Spectrum 3847. One app that keeps the team running at an event:

- **Inventory**: every tool and part, where it lives in the lab or the pit, with a map of both so nothing goes missing.
- **Event packing**: the four-stage packing workflow (Packing, Staging, Loading, Ready); each item may have one optional packing photo.
- **Borrowed tools**: track what left the pit with whom, and what came back.
- **Maps**: lab and pit layout diagrams with tappable location pins linked back to inventory items.
- **Schedule**: pit staffing and load-in/load-out shifts, with conflict detection for double-booked members.

Built with Flutter for iOS, Android, and desktop (Windows, macOS, Linux).

## Running it for your own team

The builds below talk to Spectrum 3847's Firebase project, and you cannot
repoint them from Settings, because the project is compiled in. To run the app
on your own data you fork this repository, put your own Firebase project into
it, and build it yourself. [docs/self-hosting.md](docs/self-hosting.md) is the
full walkthrough, including the sign-in function and the photo service you
have to stand up yourself.

## Install

Builds are attached to [this repo's releases](https://github.com/Spectrum3847/spectrum-pit/releases). They are unsigned, so each platform needs a step or two.

### Checksums

Every artifact on a tagged release ships with a `.sha256` file next to it, so you can check that a download arrived intact. Nightly builds do not carry one. The desktop app's built-in updater verifies its own downloads separately, against the checksum GitHub publishes with the release asset.

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

Pull requests are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md). New to Git
or Flutter? [docs/setup-guide.md](docs/setup-guide.md) starts from scratch on
Windows, macOS, and Linux.

## License

[AGPL-3.0](LICENSE). If you distribute a modified version of this app, or run one as a service for others, you must make its source available under the same license.
