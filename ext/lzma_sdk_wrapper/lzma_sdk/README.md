# LZMA SDK 26.06

This directory contains a vendored subset of the LZMA SDK version 26.06.

## License

The LZMA SDK is placed in the **public domain**.

From the official documentation:
> "Anyone is free to copy, modify, publish, use, compile, sell, or distribute the original LZMA SDK code, either in source code form or as a compiled binary, for any purpose, commercial or non-commercial, and by any means."

## Source

- Official website: https://www.7-zip.org/sdk.html
- Download: https://github.com/ip7z/7zip/releases/download/26.06/lzma2606.7z
- SHA-256: `1d9da340870b12712e9068be178a4436fbad785486b62aed6e2aa88ea1e3bb65`
- Version: 26.06

## Contents

- **C/**: ANSI-C code for LZMA/LZMA2/XZ compression and 7z archive handling
- **CPP/**: C++ code for full 7z format support and advanced features

## Usage in this project

This SDK is compiled into our custom C wrapper library (`libsevenzip_wrapper.so`/`.dylib`/`.dll`) which provides a C-compatible interface for Ruby FFI bindings.
