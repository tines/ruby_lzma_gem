# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2025-12-10

### Added
- Initial release of `ruby_lzma`
- Archive reading functionality (7z format)
- Password-protected archive support
- Memory buffer operations (StringIO/String support)
- Archive verification (`Reader#test`)
- Memory extraction (`Reader#extract_data`)
- Entry iteration and inspection
- File extraction to disk
- Block syntax with automatic cleanup
- `Entry#path` alias for `entry.name`
- FFI bindings to LZMA SDK 25.01
- RBS type signatures
- SDK version introspection (`RubyLzma.sdk_version`)
- Test suite with password-protected archive tests

### Technical Details
- Uses LZMA SDK 25.01 (public domain, Igor Pavlov)
- Three-layer architecture: C API, C++ Bridge, Ruby FFI
- Thread-safe implementation (no global state)
- Memory-safe (proper COM reference counting)
- Cross-platform support (macOS, Linux, Windows)

### Compatibility
- Drop-in alternative to `seven_zip_ruby` gem for read operations
- Supports Ruby 3.0+

