# Contributing to Spectrum Pit

Thanks for your interest. This repository is a release mirror, which changes the mechanics a little.

## How changes flow

- The team develops in a private repository. Every published release is synced here as one squashed commit.
- Pull requests here are reviewed by the maintainer. When accepted, the PR is merged here and the maintainer opens a matching PR in the internal repository, so the change ships in the next release and survives the next sync.

## Before you open a PR

- Toolchain: Flutter 3.44.4 / Dart 3.11.5.
- Run the same gates CI runs:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
```

- Keep changes small and focused, one concern per PR.
- No emojis anywhere: code, comments, docs, commit messages, or UI strings. Use plain text, or Material icons in UI.
- UI changes should keep the existing visual system: the palette tokens in `lib/src/theme/pit_palette.dart`, IBM Plex type, flat surfaces, and 8px corners for standard components (12px for sheets and dialogs).

## License

By contributing you agree that your contribution is licensed under AGPL-3.0, the same license as the project.
