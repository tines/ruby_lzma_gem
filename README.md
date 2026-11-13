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

- ✅ **Create and extract archives** - Full read/write support for 7z archives
- ✅ **Password-protected archives** - Full support for encrypted 7z files
- ✅ **Memory buffer operations** - Work with archives in memory (StringIO/String)
- ✅ **Archive verification** - Validate archive integrity before extraction
- ✅ **Configurable compression** - Multiple compression levels and methods
- ✅ **Fast operations** - Direct FFI bindings to native 7-Zip SDK
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

### Creating Archives

```ruby
require 'ruby_lzma'

# Create a new archive
RubyLzma::Archive::Writer.open('archive.7z') do |writer|
  # Add files from disk
  writer.add_file('/path/to/file.txt', 'file.txt')
  
  # Add data from memory
  writer.add_data('Hello, World!', 'greeting.txt')
  
  # Create directories
  writer.mkdir('empty_folder')
end

# Create encrypted archive with compression options
RubyLzma::Archive::Writer.open('secure.7z', 
  password: 'secret123',
  level: RubyLzma::Archive::Writer::LEVEL_ULTRA
) do |writer|
  writer.add_file('/path/to/sensitive.pdf', 'documents/sensitive.pdf')
  writer.add_data(secret_data, 'data/secrets.bin')
end
```

### Extracting Archives

```ruby
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

- **Creating Archives**: Add files, add data from memory, compression options
- **Extracting Archives**: List contents, extract files, pattern matching
- **Password-Protected Archives**: Working with encrypted archives (read/write)
- **Memory Operations**: HTTP downloads, database storage, stream processing
- **Advanced Usage**: Metadata inspection, verification, concurrent processing
- **Error Handling**: Comprehensive error recovery patterns

## API Reference

### RubyLzma Module

```ruby
RubyLzma::VERSION          # => "0.1.0" (gem version)
RubyLzma.sdk_version       # => "26.06" (LZMA SDK version)
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

### Writer Class

| Method | Description | Returns |
|--------|-------------|---------|
| `new(path, format:, password:, level:)` | Create writer for file | Writer |
| `open(path, ...)` | Open file with auto-close | Writer (or block result) |
| `add_file(source, archive_path)` | Add file from disk | void |
| `add_data(data, archive_path)` | Add data from memory | void |
| `add_directory(source, archive_path)` | Add directory recursively | void |
| `mkdir(archive_path)` | Create empty directory | void |
| `size` / `count` / `length` | Entry count | Integer |
| `close` | Finalize and write archive | void |
| `closed?` | Check if closed | Boolean |

#### Compression Levels

```ruby
RubyLzma::Archive::Writer::LEVEL_STORE    # No compression (fastest)
RubyLzma::Archive::Writer::LEVEL_FASTEST  # Minimal compression
RubyLzma::Archive::Writer::LEVEL_FAST     # Fast compression
RubyLzma::Archive::Writer::LEVEL_NORMAL   # Balanced (default)
RubyLzma::Archive::Writer::LEVEL_MAXIMUM  # High compression
RubyLzma::Archive::Writer::LEVEL_ULTRA    # Maximum compression (slowest)
```

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

# Compression levels (used with Writer)
RubyLzma::FFI::Constants::SZ_LEVEL_STORE    # => 0 (no compression)
RubyLzma::FFI::Constants::SZ_LEVEL_FASTEST  # => 1
RubyLzma::FFI::Constants::SZ_LEVEL_FAST     # => 3
RubyLzma::FFI::Constants::SZ_LEVEL_NORMAL   # => 5 (default)
RubyLzma::FFI::Constants::SZ_LEVEL_MAXIMUM  # => 7
RubyLzma::FFI::Constants::SZ_LEVEL_ULTRA    # => 9 (best compression)
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

1. **C API** (`lzma_sdk_wrapper.h/c`) - Clean C interface for archive operations
2. **C++ Bridge** (`cpp_bridge.cpp`) - LZMA SDK COM interface wrapper (IInArchive/IOutArchive)
3. **Ruby FFI** (`lib/ffi/`) - Ruby bindings via FFI

Key classes:
- `RubyLzma::Archive::Reader` - Read and extract from archives
- `RubyLzma::Archive::Writer` - Create new archives
- `RubyLzma::Entry` - Archive entry metadata

This architecture provides:
- Type safety (C API contract)
- Performance (direct FFI calls, native LZMA2 compression)
- Maintainability (clear separation of concerns)
- Memory safety (no leaks in native code)

## Security

This library includes protection against common archive-related security vulnerabilities.

### Zip Slip Protection (Path Traversal)

The `Writer` class sanitizes all archive paths to prevent Zip Slip attacks:

```ruby
# These will raise RubyLzma::Archive::Writer::PathTraversalError
writer.add_data("data", "../../../etc/passwd")  # Parent traversal
writer.add_data("data", "/etc/passwd")           # Absolute path
writer.add_data("data", "foo\x00bar.txt")        # Null bytes
```

The `Reader` class validates extraction paths during `extract_all`:

```ruby
# Paths are validated to stay within the target directory
reader.extract_all("/safe/output/dir")
```

### Archive Bomb Protection

The library protects against archive bomb (zip bomb) attacks with configurable limits:

```ruby
# Default limits (class-level configuration)
RubyLzma::Archive::Reader.max_entry_size       # 1 GB per entry
RubyLzma::Archive::Reader.max_total_size       # 10 GB total
RubyLzma::Archive::Reader.max_compression_ratio # 1000:1 ratio

# Customize limits
RubyLzma::Archive::Reader.max_entry_size = 100 * 1024 * 1024  # 100 MB
RubyLzma::Archive::Reader.max_compression_ratio = 500         # 500:1

# Disable specific limits (use with caution)
RubyLzma::Archive::Reader.max_entry_size = nil
```

When limits are exceeded, `ExtractionLimitError` is raised with a helpful message:

```ruby
begin
  reader.extract_data(entry)
rescue RubyLzma::Archive::Reader::ExtractionLimitError => e
  puts e.message  # Includes instructions to disable limit if needed
end
```

## Limitations

Current version supports **reading and writing** 7z archives:
- ✅ Create archives
- ✅ Extract archives
- ✅ Password-protected archives (read/write)
- ✅ Memory operations (add data from memory, extract to memory)
- ✅ Configurable compression levels
- ❌ Modify existing archives (append/delete entries)
- ❌ Multi-volume archives
- ❌ ZIP/TAR formats (7z only)


## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing`)
3. Commit your changes (`git commit -am 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing`)
5. Open a Pull Request

## License

This gem is released under the MIT License. See [LICENSE](LICENSE) for details.

The embedded LZMA SDK is **public domain** (Igor Pavlov).

## Credits

- **LZMA SDK**: Igor Pavlov (https://www.7-zip.org/)

## Support

- **Issues**: https://github.com/tines/ruby_lzma/issues
<!-- - **Documentation**: https://rubydoc.info/gems/ruby_lzma -->


## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.
