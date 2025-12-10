# RubyLzma

> ⚠️ **Experimental Software** ⚠️
>
> This gem is under active development and is subject to change at any time without notice. The API is not yet stable and breaking changes may occur in any release, including minor and patch versions.
>
> **If you use this gem, pin your version explicitly:**
> ```ruby
> gem 'ruby_lzma', '= 0.1.0'
> ```
>
> There is no guarantee of backwards compatibility until a 1.0 release.

A Ruby gem providing FFI bindings to the LZMA SDK (7-Zip) for archive operations. 

## Features

- ✅ **Password-protected archives** - Full support for encrypted 7z files
- ✅ **Memory buffer operations** - Work with archives in memory (StringIO/String)
- ✅ **Archive verification** - Validate archive integrity before extraction
- ✅ **Fast extraction** - Direct FFI bindings to native 7-Zip SDK
- ✅ **Type hints** - RBS type signatures included
- ✅ **Thread-safe** - No global state

## Installation

Add to your Gemfile:

```ruby
gem 'ruby_lzma'
```

Then run:

```bash
bundle install
```

Or install directly:

```bash
gem install ruby_lzma
```

### Building from Source

```bash
git clone https://github.com/tines/ruby_lzma.git
cd ruby_lzma
bundle install
rake compile
```

## Quick Start

```ruby
require 'ruby_lzma'

# Extract all files from an archive
RubyLzma::Archive::Reader.open('archive.7z') do |reader|
  reader.extract_all('/output/directory')
end

# With password protection
RubyLzma::Archive::Reader.open('encrypted.7z', password: 'secret') do |reader|
  # List entries
  reader.entries.each do |entry|
    puts "#{entry.name}: #{entry.size} bytes"
  end
  
  # Extract single file
  reader.extract(0, '/output/file.txt')
end

# Extract from memory (StringIO)
archive_data = File.binread('archive.7z')
RubyLzma::Archive::Reader.open_buffer(archive_data, password: 'secret') do |reader|
  data = reader.extract_data(0)  # Extract first file to memory
  puts "Extracted: #{data.bytesize} bytes"
end
```

## Usage Examples

For detailed usage examples, see [EXAMPLES.md](EXAMPLES.md) which covers:

- **Basic Operations**: List contents, extract files, pattern matching
- **Password-Protected Archives**: Working with encrypted archives, password recovery
- **Memory Operations**: HTTP downloads, database storage, stream processing
- **Advanced Usage**: Metadata inspection, verification, concurrent processing
- **Error Handling**: Comprehensive error recovery patterns

## API Reference

### RubyLzma Module

```ruby
RubyLzma::VERSION          # => "0.1.0" (gem version)
RubyLzma.sdk_version       # => "25.01" (LZMA SDK version)
RubyLzma.sdk_info          # => Full SDK info with copyright
```

### Reader Class

| Method | Description | Returns |
|--------|-------------|---------|
| `new(path, format:, password:)` | Create reader for file | Reader |
| `open(path, ...)` | Open file with auto-close | Reader (or block result) |
| `open_buffer(buffer, ...)` | Open from memory | Reader (or block result) |
| `size` / `count` / `length` | Entry count | Integer |
| `entries` | All entries | Array<Entry> |
| `each` | Iterate entries | Enumerator |
| `[index]` | Get entry by index | Entry |
| `extract(entry, path)` | Extract to file | void |
| `extract_all(dir, full_paths:)` | Extract all | void |
| `extract_data(entry)` | Extract to memory | String |
| `test` | Verify archive | Boolean |
| `close` | Close archive | void |
| `closed?` | Check if closed | Boolean |

### Entry Class

| Attribute | Type | Description |
|-----------|------|-------------|
| `index` | Integer | Entry index |
| `name` / `path` | String | Entry path |
| `size` | Integer | Uncompressed size |
| `compressed_size` | Integer | Compressed size |
| `crc` | Integer | CRC32 checksum |
| `modified_time` | Integer | Unix timestamp |
| `attributes` | Integer | File attributes |
| `directory?` | Boolean | Is directory? |
| `file?` | Boolean | Is file? |
| `mtime` | Time | Modified time |

### Constants

```ruby
# Archive formats
RubyLzma::FFI::Constants::SZ_FORMAT_7Z   # => 0
RubyLzma::FFI::Constants::SZ_FORMAT_ZIP  # => 1
RubyLzma::FFI::Constants::SZ_FORMAT_TAR  # => 2

# Compression levels (for future Writer support)
RubyLzma::FFI::Constants::SZ_LEVEL_STORE    # => 0
RubyLzma::FFI::Constants::SZ_LEVEL_FASTEST  # => 1
RubyLzma::FFI::Constants::SZ_LEVEL_FAST     # => 3
RubyLzma::FFI::Constants::SZ_LEVEL_NORMAL   # => 5
RubyLzma::FFI::Constants::SZ_LEVEL_MAXIMUM  # => 7
RubyLzma::FFI::Constants::SZ_LEVEL_ULTRA    # => 9
```

## Type Hints

The gem includes RBS type signatures in `sig/ruby_lzma.rbs`. Enable type checking with:

```bash
# Steep
steep check

# TypeProf
typeprof lib/**/*.rb
```

## Development

### Running Tests

```bash
bundle exec rspec
```

### Building Native Extension

```bash
cd ext/lzma_sdk_wrapper
ruby extconf.rb
make
```

### Updating LZMA SDK

See [SDK_UPDATE.md](SDK_UPDATE.md) for detailed instructions on updating the embedded LZMA SDK.

## Architecture

The gem consists of three layers:

1. **C API** (`lzma_sdk_wrapper.h/c`) - Clean C interface
2. **C++ Bridge** (`cpp_bridge.cpp`) - LZMA SDK COM interface wrapper
3. **Ruby FFI** (`lib/ffi/`) - Ruby bindings via FFI

This architecture provides:
- Type safety (C API contract)
- Performance (direct FFI calls)
- Maintainability (clear separation of concerns)

## Limitations

Current version focuses on **reading** archives:
- ✅ Extract archives
- ✅ Password-protected archives
- ✅ Memory operations
- ❌ Create archives 
- ❌ Modify archives
- ❌ Multi-volume archives


## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing`)
3. Commit your changes (`git commit -am 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing`)
5. Open a Pull Request

## License

This gem is released under the MIT License. See [LICENSE.txt](LICENSE.txt) for details.

The embedded LZMA SDK is **public domain** (Igor Pavlov).

## Credits

- **LZMA SDK**: Igor Pavlov (https://www.7-zip.org/)

## Support

- **Issues**: https://github.com/tines/ruby_lzma/issues
<!-- - **Documentation**: https://rubydoc.info/gems/ruby_lzma -->


## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.
