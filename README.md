# Hafiportrait Manager

> Enterprise-grade desktop application for professional photo management, high-performance file copy operations, and seamless cloud publishing to Cloudflare R2 and Google Drive.

[![Flutter](https://img.shields.io/badge/Flutter-3.41%2B-blue.svg)](https://flutter.dev)
[![Rust](https://img.shields.io/badge/Rust-stable-orange.svg)](https://rust-lang.org)
[![License](https://img.shields.io/badge/License-Proprietary-purple.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/Platforms-Linux%20%7C%20Windows-lightgrey.svg)](#)

## Table of Contents

1. [Overview](#overview)
2. [Features](#features)
3. [Architecture](#architecture)
4. [Technology Stack](#technology-stack)
5. [Project Structure](#project-structure)
6. [Prerequisites](#prerequisites)
7. [Setup](#setup)
8. [Usage](#usage)
9. [Testing](#testing)
10. [CI/CD](#cicd)
11. [Security](#security)
12. [Troubleshooting](#troubleshooting)
13. [Contributing](#contributing)
14. [License](#license)

---

## Overview

**Hafiportrait Manager** (formerly `filecopy_utility`) is a professional-grade desktop application designed for photographers and creative professionals who need efficient workflow tools for:

- **High-performance file copy** with parallel processing, pause/resume, and integrity verification
- **Smart gallery management** with recursive scanning and RAW/JPG support
- **Cloud publishing** to Cloudflare R2 and Google Drive with automatic thumbnail/preview generation
- **Batch processing** with progress tracking and detailed logging

The application combines Flutter's modern UI capabilities with Rust's raw performance for computationally intensive tasks like image processing and file operations.

---

## Features

### Core Features

| Feature | Description |
|---------|-------------|
| **Smart File Copy** | Parallel copy with SHA-256 verification, pause/resume/cancel, duplicate handling |
| **Gallery Scanner** | Recursive scanning, RAW/JPG/PNG support, thumbnail generation |
| **Cloud Publishing** | Upload to Cloudflare R2 + Google Drive with manifest generation |
| **Profile Management** | Save and load copy configurations for recurring workflows |
| **Dual Theme** | Glassmorphism dark/light themes with Material 3 design |
| **Multi-platform** | Linux and Windows support |

### Advanced Features

- **Retry Mechanism** - Exponential backoff with jitter for resilient uploads
- **Progress Tracking** - Real-time progress with ETA estimation
- **Error Handling** - Comprehensive error recovery and detailed logging
- **Security** - Secure credential storage via platform keychain
- **Extensibility** - Provider-based architecture for easy customization

---

## Architecture

### Design Patterns

```
┌─────────────────────────────────────────────────────────────┐
│                        UI Layer                             │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────┐ │
│  │ MainScreen  │ │ GalleryPage │ │   PublishPage       │ │
│  └─────────────┘ └─────────────┘ └─────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    State Management                         │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────┐ │
│  │ CopyProvider│ │UploadProvider│ │ SettingsProvider   │ │
│  └─────────────┘ └─────────────┘ └─────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     Service Layer                           │
│  ┌─────────────────┐ ┌────────────────┐ ┌───────────────┐  │
│  │FileOperation   │ │Upload          │ │Cloud Services │  │
│  │Service         │ │Orchestrator    │ │(R2/Drive)    │  │
│  └─────────────────┘ └────────────────┘ └───────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Native Layer (Rust)                       │
│  ┌────────────┐ ┌────────────┐ ┌───────────────────────┐  │
│  │File Copy   │ │Hash/Verify │ │ Image Processing     │  │
│  │(parallel)  │ │(SHA-256)   │ │ (WebP encoding)      │  │
│  └────────────┘ └────────────┘ └───────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### State Management

The application uses **Riverpod** for reactive state management:

- **Providers** - Immutable state slices with `select()` for efficient rebuilds
- **StateNotifiers** - Complex state with actions
- **Async Providers** - For async operations like file I/O

### Service Layer

| Service | Responsibility |
|---------|----------------|
| `FileOperationService` | File validation, copy with progress, folder scanning |
| `UploadOrchestrator` | Coordinates full upload pipeline |
| `R2UploadService` | Cloudflare R2 (S3-compatible) uploads via Minio |
| `GoogleDriveUploadService` | OAuth2 authentication and Drive uploads |
| `ProfileService` | Profile persistence (app support directory) |

---

## Technology Stack

### Frontend

| Technology | Version | Purpose |
|------------|---------|---------|
| Flutter | 3.41+ | UI Framework |
| Riverpod | 2.6.1 | State Management |
| file_picker | 8.1.6 | File/Folder selection |
| desktop_drop | 0.5.0 | Drag and drop support |
| shared_preferences | 2.3.4 | Settings persistence |
| flutter_secure_storage | 9.2.4 | Secure credential storage |
| googleapis | 16.0.0 | Google Drive API |
| minio | 3.5.8 | S3-compatible uploads |

### Backend (Rust)

| Crate | Version | Purpose |
|-------|---------|---------|
| flutter_rust_bridge | 2.9.0 | FFI bindings |
| tokio | 1.x | Async runtime |
| rayon | 1.x | Parallel processing |
| image | 0.25 | Image processing |
| webp | 0.2.6 | WebP encoding |
| sha2 | 0.10 | SHA-256 hashing |
| walkdir | 2.x | Directory traversal |

### Development

| Tool | Purpose |
|------|---------|
| flutter_rust_bridge_codegen | Generate FFI bindings |
| dart format | Code formatting |
| cargo clippy | Rust linting |
| GitHub Actions | CI/CD |

---

## Project Structure

```
apps-flutter/
├── .github/workflows/     # CI/CD configurations
│   └── flutter_build.yml
├── assets/images/         # App assets
│   └── logo.png
├── integration_test/     # E2E tests
│   └── app_flow_test.dart
├── lib/                  # Dart source code
│   ├── main.dart         # Entry point
│   ├── app.dart          # App widget
│   ├── models/           # Data models
│   │   ├── file_item.dart
│   │   ├── cloud_account.dart
│   │   ├── copy_profile.dart
│   │   ├── copy_result.dart
│   │   ├── performance_settings.dart
│   │   └── scheduled_task.dart
│   ├── providers/        # Riverpod providers
│   │   ├── copy_provider.dart
│   │   ├── settings_provider.dart
│   │   ├── upload_provider.dart
│   │   └── publish_history_provider.dart
│   ├── screens/          # UI screens
│   │   ├── main_screen.dart
│   │   ├── gallery_page.dart
│   │   ├── publish_page.dart
│   │   └── settings_page.dart
│   ├── services/         # Business logic
│   │   ├── file_operation_service.dart
│   │   ├── upload_orchestrator.dart
│   │   ├── r2_upload_service.dart
│   │   ├── google_drive_upload_service.dart
│   │   ├── profile_service.dart
│   │   └── file_picker_adapter.dart
│   ├── widgets/          # Reusable widgets
│   │   └── glass_widgets.dart
│   ├── theme/           # Theming
│   │   ├── glass_theme.dart
│   │   └── glass_colors.dart
│   └── src/rust/       # Generated FFI bindings
│       ├── api.dart
│       └── frb_generated.dart
├── rust/                 # Rust source code
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs
│       ├── api.rs
│       ├── file_copy.rs
│       ├── hash.rs
│       ├── image_processing.rs
│       ├── parallel.rs
│       └── platform/
│           ├── mod.rs
│           ├── linux.rs
│           └── windows.rs
├── test/                 # Unit tests
│   └── widget_test.dart
├── pubspec.yaml
├── flutter_rust_bridge.yaml
├── analysis_options.yaml
├── README.md
└── AUDIT_REPORT.md
```

---

## Prerequisites

### System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| OS | Ubuntu 20.04+ / Windows 10+ | Ubuntu 22.04+ / Windows 11 |
| RAM | 4 GB | 8 GB |
| Disk | 500 MB | 1 GB |
| Flutter | 3.41+ stable | Latest stable |
| Rust | 1.70+ stable | Latest stable |

### Build Dependencies

#### Ubuntu/Debian

```bash
# Flutter dependencies
sudo apt-get install -y \
  clang \
  cmake \
  ninja-build \
  pkg-config \
  libgtk-3-dev \
  liblzma-dev \
  libstdc++-12-dev \
  libsecret-1-dev \
  lld \
  llvm

# Optional: for development
sudo apt-get install -y git curl unzip xz-utils
```

#### Windows

- Visual Studio 2022+ with C++ desktop development
- Windows 10/11 SDK
- Rust toolchain (via rustup)

### Account Requirements

| Service | Required | Notes |
|---------|----------|-------|
| Cloudflare R2 | Yes | Account ID, Access Key, Secret Key, Bucket |
| Google Drive | No | OAuth2 credentials.json (not stored in repo) |

---

## Setup

### 1. Clone Repository

```bash
git clone <repository-url>
cd apps-flutter
```

### 2. Install Flutter Dependencies

```bash
flutter pub get
```

### 3. Install Rust FFI Codegen

```bash
cargo install flutter_rust_bridge_codegen@2.9.0
```

### 4. Generate FFI Bindings

```bash
flutter_rust_bridge_codegen generate
```

### 5. Verify Setup

```bash
# Run analysis
flutter analyze

# Run tests
flutter test
```

---

## Usage

### Quick Start

#### 1. Launch Application

```bash
# Linux
flutter run -d linux

# Windows
flutter run -d windows
```

### Copy Workflow

1. **Select Source Folder** - Click "Browse" or drag folder
2. **Import File List** - Paste or import TXT/CSV with filenames
3. **Validate** - Click "Validate" to match files
4. **Configure** - Set destination and options
5. **Copy** - Click "Start Copy" with progress tracking

### Publish Workflow

1. **Navigate to Publish** - Click cloud icon in sidebar
2. **Configure Event** - Enter event name
3. **Select Source** - Choose photo folder
4. **Choose Account** - Select R2 account
5. **Optional: Google Drive** - Enable original upload
6. **Publish** - Click "Publish Gallery"

### Settings Configuration

Access via gear icon in sidebar:

| Category | Options |
|---------|---------|
| Theme | Dark/Light mode |
| Copy Behavior | Skip existing, duplicate handling, parallelism |
| Performance | Copy mode, max parallelism |
| Cloud Accounts | R2 accounts, Google Drive credentials |

---

## Testing

### Unit Tests

```bash
# Run all unit tests
flutter test

# Run with coverage
flutter test --coverage
```

### Integration Tests

```bash
# Run E2E tests (requires display)
flutter test integration_test/app_flow_test.dart

# Or with Xvfb (Linux headless)
xvfb-run -a flutter test integration_test/app_flow_test.dart
```

### Code Quality

```bash
# Static analysis
flutter analyze

# Format check
dart format --output=none --set-exit-if-changed .

# Rust linting
cd rust && cargo clippy --all-targets --all-features -- -D warnings
```

---

## CI/CD

### GitHub Actions Workflow

The project includes automated CI/CD for Linux and Windows:

#### Linux (Ubuntu)

```yaml
- Checkout
- Setup Flutter (with caching)
- Setup Rust (with caching)
- Get Dependencies
- Check Dart Format
- Rust fmt / clippy
- Analyze
- Run Tests
- Generate FFI Bindings
- Build Linux Release
```

#### Windows

Same steps with Windows-specific toolchain.

### Running CI Locally

```bash
# Simulate CI build
flutter build linux --release

# Check all CI steps
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
cd rust && cargo fmt --all -- --check && cargo clippy --all-targets -- -D warnings
```

---

## Security

### Credential Management

| Storage | Method |
|---------|--------|
| R2 Keys | flutter_secure_storage (OS keychain) |
| Google Drive | External credentials.json |
| App Settings | shared_preferences (non-sensitive) |

### Security Best Practices

- **Never commit** `credentials.json` to repository
- Use environment variables for CI/CD secrets
- Validate all file paths to prevent traversal
- Hash verification for file integrity
- Secure storage for API keys

### Audit

See [AUDIT_REPORT.md](AUDIT_REPORT.md) for security findings and remediation status.

---

## Troubleshooting

### Common Issues

#### Flutter Issues

| Error | Solution |
|-------|----------|
| `package not found` | Run `flutter pub get` |
| `version conflict` | Run `flutter pub upgrade` |
| `analysis errors` | Run `flutter analyze` to see details |

#### Rust/FFI Issues

| Error | Solution |
|-------|----------|
| `undefined symbol` | Regenerate bindings: `flutter_rust_bridge_codegen generate` |
| `linker error` | Install build dependencies (see Prerequisites) |
| `cargo not found` | Install Rust: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh` |

#### Platform Issues

| Platform | Issue | Solution |
|----------|-------|----------|
| Linux | Missing GTK | `sudo apt install libgtk-3-dev` |
| Linux | Missing keychain | `sudo apt install libsecret-1-dev` |
| Windows | VS not found | Install Visual Studio with C++ workload |

#### Cloud Upload Issues

| Error | Solution |
|-------|----------|
| R2 connection failed | Verify credentials in Settings |
| Drive auth failed | Re-authenticate in Settings |
| Upload timeout | Retry mechanism should handle automatically |

### Getting Help

1. Check [AUDIT_REPORT.md](AUDIT_REPORT.md) for known issues
2. Run `flutter analyze` for code issues
3. Check logs in application UI
4. Review CI/CD logs for build issues

---

## Contributing

### Development Workflow

```bash
# Create feature branch
git checkout -b feature/your-feature

# Make changes
# ... edit code ...

# Run tests
flutter analyze
flutter test

# Commit with conventional messages
git commit -m "feat: add new feature"

# Push and create PR
git push origin feature/your-feature
```

### Code Style

- Follow [Dart style guide](https://dart.dev/guides/language/effective-dart)
- Use `dart format` before commit
- Run `cargo clippy` for Rust code

### Testing Requirements

- All new features require tests
- Run `flutter test` before PR
- Integration tests for UI flows

---

## License

Proprietary - All rights reserved.

See [LICENSE](LICENSE) file for details.

---

## Acknowledgments

- [Flutter](https://flutter.dev) - UI framework
- [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge) - FFI solution
- [Minio](https://min.io/) - S3-compatible storage
- [Google Drive API](https://developers.google.com/drive/api) - Cloud storage

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.0.0 | 2026-02 | Major release with Rust FFI, retry mechanism, E2E tests |
| 1.0.0 | Earlier | Initial release |

---

For questions or support, please refer to the issue tracker or contact the development team.
