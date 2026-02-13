# Hafiportrait Manager (filecopy_utility)

Desktop Flutter app for fast photo copy, gallery preview, and publishing to
Cloudflare R2 + Google Drive. Includes Rust image processing via
flutter_rust_bridge.

## Requirements

- Flutter (stable channel)
- Rust toolchain (stable)
- flutter_rust_bridge_codegen (for bindings)

## Setup

```bash
flutter pub get
cargo install flutter_rust_bridge_codegen@2.9.0
flutter_rust_bridge_codegen generate
```

## Run

```bash
flutter run -d linux
```

## Build

```bash
flutter build linux --release
```

## Tests

```bash
flutter analyze
flutter test
```

## Notes

- `credentials.json` for Google Drive OAuth is not stored in this repo.
