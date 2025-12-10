# LZMA SDK Update Guide

This document describes how to update the embedded LZMA SDK to a newer version.

## Current SDK Version

The library currently uses LZMA SDK version **25.01** (August 3, 2025).

You can check the current version programmatically:

```ruby
require 'ruby_lzma'

puts RubyLzma.sdk_version  # => "25.01"
puts RubyLzma.sdk_info     # => Full version with copyright
```

## Why Update?

- **Security fixes**: New SDK versions may include security patches
- **Performance improvements**: Newer versions often have optimizations
- **Bug fixes**: SDK bugs are fixed in newer releases
- **New features**: Support for additional compression methods or formats

## Update Process

### 1. Download the Latest SDK

1. Visit the official 7-Zip SDK download page: https://www.7-zip.org/sdk.html
2. Download the latest LZMA SDK (e.g., `lzma2501.7z`)
3. Extract the archive

### 2. Backup Current SDK

```bash
cd ext/lzma_sdk_wrapper
mv lzma_sdk lzma_sdk.backup
```

### 3. Copy New SDK Files

```bash
# From the extracted SDK directory
cp -r /path/to/extracted/lzma_sdk ext/lzma_sdk_wrapper/
```

The SDK should contain these directories:
- `C/` - C API
- `CPP/` - C++ API (7z format handler)

### 4. Verify SDK Structure

Ensure these critical files exist:

```
ext/lzma_sdk_wrapper/lzma_sdk/
├── C/
│   ├── 7z.h
│   ├── 7zAlloc.c
│   ├── 7zVersion.h  ← Version info
│   └── ... (other C API files)
└── CPP/
    ├── 7zip/
    │   ├── Archive/
    │   │   └── 7z/  ← 7z format handler
    │   └── Common/
    └── Common/
        └── MyCom.h  ← COM support
```

### 5. Update Gem Version (Optional)

If the SDK update includes significant changes, consider updating the gem version in `lib/ruby_lzma/version.rb`:

```ruby
module RubyLzma
  VERSION = "0.2.0"  # Bump version
end
```

**Versioning strategy:**
- Gem version follows semantic versioning (MAJOR.MINOR.PATCH)
- Gem version is **independent** of SDK version
- SDK version is automatically pulled from `lzma_sdk/C/7zVersion.h`

### 6. Test Compilation

```bash
cd ext/lzma_sdk_wrapper
make clean
make
```

Expected output: Clean compilation with no errors.

### 7. Run Test Suite

```bash
cd ../../  # Back to project root
bundle exec rspec
```

All tests should pass.

### 8. Test with Tines Backend Pattern

Create a test script that mimics Tines usage:

```ruby
require 'stringio'
require 'ruby_lzma'

# Read test archive
data = File.binread('spec/fixtures/test_encrypted.7z')

# Test Tines pattern
RubyLzma::Archive::Reader.open_buffer(StringIO.new(data), password: 'TestPass123') do |reader|
  unless reader.test
    raise "Archive validation failed!"
  end

  files = reader.entries.map.with_index do |entry, i|
    { name: entry.path, data: reader.extract_data(i) }
  end

  puts "✓ Successfully extracted #{files.size} files"
end
```

### 9. Check for API Changes

Review the SDK changelog for breaking changes:

1. Check `lzma_sdk/history.txt` for changes
2. Look for deprecated or removed functions
3. Check for new required initialization steps

**Common areas to check:**
- `IInArchive` interface changes (affects memory buffer support)
- `IArchiveExtractCallback` interface changes (affects extraction)
- Property IDs in `PropID.h` (affects entry info retrieval)
- COM interface changes (affects all C++ API usage)

### 10. Handle Breaking Changes

If the SDK introduces breaking changes:

#### a. C API Changes

Update affected code in:
- `ext/lzma_sdk_wrapper/cpp_bridge.cpp`
- `ext/lzma_sdk_wrapper/cpp_bridge.hpp`

#### b. Property ID Changes

If property IDs changed, update `getEntryInfo()` in `cpp_bridge.cpp`:

```cpp
// Example: If kpidPath changes
hr = archive->GetProperty(index, kpidPath, &prop);  // Update this line
```

#### c. Interface Changes

Update callback classes in `archive_callbacks.cpp` if interfaces changed.

### 11. Update Documentation

After successful update:

1. Update this file with the new SDK version
2. Update README.md if new features are available
3. Update CHANGELOG.md with SDK version change
4. Document any behavior changes

### 12. Commit Changes

```bash
git add ext/lzma_sdk_wrapper/lzma_sdk
git commit -m "Update LZMA SDK to version X.XX"
```

## Troubleshooting

### Compilation Errors

**Problem**: Undefined references to 7z functions
- **Solution**: Check that all required .c/.cpp files are listed in `extconf.rb`

**Problem**: COM interface compilation errors
- **Solution**: Verify C++ standard is set correctly in extconf.rb (`-std=c++11`)

**Problem**: Property access errors
- **Solution**: Check if property IDs changed in the new SDK

### Runtime Errors

**Problem**: Segmentation faults
- **Solution**: Check for ABI changes in COM interfaces. You may need to update callback classes.

**Problem**: Memory leaks
- **Solution**: Verify COM reference counting is correct (AddRef/Release calls)

**Problem**: Password not working
- **Solution**: Check if `ICryptoGetTextPassword` interface changed

## SDK Version Compatibility

| Gem Version | SDK Version | Tested |
|-------------|-------------|--------|
| 0.1.0       | 25.01       | ✅ Yes  |

## Additional Resources

- **Official 7-Zip SDK**: https://www.7-zip.org/sdk.html
- **SDK Source Code**: https://github.com/ip7z/7zip (unofficial mirror)
- **Format Documentation**: https://www.7-zip.org/7z.html

## Notes

- The SDK is **public domain** (Igor Pavlov)
- Always test thoroughly after updating
- Consider updating during a minor version bump
- Keep the old SDK backup until tests pass
- Document any workarounds needed for the new version
