# LZMA SDK 25.01

This directory contains a vendored subset of the LZMA SDK version 25.01.

## License

The LZMA SDK is placed in the **public domain**.

From the official documentation:
> "Anyone is free to copy, modify, publish, use, compile, sell, or distribute the original LZMA SDK code, either in source code form or as a compiled binary, for any purpose, commercial or non-commercial, and by any means."

## Source

- Official website: https://www.7-zip.org/sdk.html
- Download: https://www.7-zip.org/a/lzma2501.7z
- Version: 25.01

## Contents

- **C/**: ANSI-C code for LZMA/LZMA2/XZ compression and 7z archive handling
- **CPP/**: C++ code for full 7z format support and advanced features

## Usage in this project

This SDK is compiled into our custom C wrapper library (`libsevenzip_wrapper.so`/`.dylib`/`.dll`) which provides a C-compatible interface for Ruby FFI bindings.
