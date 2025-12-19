# RubyLzma Examples

This document provides practical examples of using the ruby_lzma gem.

## Table of Contents

- [Basic Operations](#basic-operations)
- [Password-Protected Archives](#password-protected-archives)
- [Memory Operations](#memory-operations)
- [Advanced Usage](#advanced-usage)
- [Error Handling](#error-handling)

## Basic Operations

### List Archive Contents

```ruby
require 'ruby_lzma'

RubyLzma::Archive::Reader.open('archive.7z') do |reader|
  puts "Archive contains #{reader.size} files:"
  
  reader.entries.each do |entry|
    type = entry.directory? ? "DIR " : "FILE"
    size = entry.directory? ? "-" : "#{entry.size} bytes"
    puts "  [#{type}] #{entry.name.ljust(40)} #{size}"
  end
end
```

### Extract All Files

```ruby
require 'ruby_lzma'

# Extract preserving directory structure
RubyLzma::Archive::Reader.open('archive.7z') do |reader|
  reader.extract_all('/output/path')
  puts "Extracted #{reader.size} files"
end

# Extract all files to flat directory (no subdirectories)
RubyLzma::Archive::Reader.open('archive.7z') do |reader|
  reader.extract_all('/output/path', full_paths: false)
end
```

### Extract Specific Files

```ruby
require 'ruby_lzma'

RubyLzma::Archive::Reader.open('archive.7z') do |reader|
  # Find a specific file
  readme = reader.entries.find { |e| e.name == 'README.md' }
  
  if readme
    reader.extract(readme, '/tmp/README.md')
    puts "Extracted #{readme.name}"
  else
    puts "README.md not found in archive"
  end
end
```

### Extract Files Matching Pattern

```ruby
require 'ruby_lzma'

RubyLzma::Archive::Reader.open('archive.7z') do |reader|
  # Extract all .txt files
  reader.entries.each_with_index do |entry, i|
    if entry.name.end_with?('.txt')
      output_path = File.join('/output', File.basename(entry.name))
      reader.extract(i, output_path)
      puts "Extracted: #{entry.name}"
    end
  end
end
```

## Password-Protected Archives

### Open with Password

```ruby
require 'ruby_lzma'

password = ENV['ARCHIVE_PASSWORD'] || 'secret'

RubyLzma::Archive::Reader.open('encrypted.7z', password: password) do |reader|
  # Verify password is correct
  unless reader.test
    raise "Invalid password or corrupt archive"
  end
  
  reader.extract_all('/output')
end
```

### Try Multiple Passwords

```ruby
require 'ruby_lzma'

passwords = ['password123', 'secret', 'admin', '12345']
archive_path = 'encrypted.7z'

successful_password = nil

passwords.each do |password|
  begin
    RubyLzma::Archive::Reader.open(archive_path, password: password) do |reader|
      if reader.test
        successful_password = password
        puts "Password found: #{password}"
        break
      end
    end
  rescue RubyLzma::Error
    # Password incorrect, try next
    next
  end
  
  break if successful_password
end

if successful_password
  # Extract with correct password
  RubyLzma::Archive::Reader.open(archive_path, password: successful_password) do |reader|
    reader.extract_all('/output')
  end
else
  puts "No valid password found"
end
```

## Memory Operations

### Load from HTTP Response

```ruby
require 'ruby_lzma'
require 'net/http'
require 'stringio'

# Download archive to memory
uri = URI('https://example.com/archive.7z')
response = Net::HTTP.get_response(uri)

if response.is_a?(Net::HTTPSuccess)
  # Extract directly from memory
  RubyLzma::Archive::Reader.open_buffer(response.body, password: 'secret') do |reader|
    reader.entries.each_with_index do |entry, i|
      data = reader.extract_data(i)
      File.binwrite(File.join('/output', entry.name), data)
    end
  end
else
  puts "Failed to download: #{response.code}"
end
```

### Extract to Memory (Database Storage)

```ruby
require 'ruby_lzma'
require 'pg'  # PostgreSQL example

archive_data = File.binread('documents.7z')
conn = PG.connect(dbname: 'mydb')

RubyLzma::Archive::Reader.open_buffer(archive_data, password: 'secret') do |reader|
  reader.entries.each_with_index do |entry, i|
    next if entry.directory?
    
    # Extract to memory
    content = reader.extract_data(i)
    
    # Store in database
    conn.exec_params(
      'INSERT INTO documents (name, content, size) VALUES ($1, $2, $3)',
      [entry.name, content, entry.size]
    )
    
    puts "Stored: #{entry.name} (#{entry.size} bytes)"
  end
end

conn.close
```

### Stream Processing

```ruby
require 'ruby_lzma'

archive_data = File.binread('logs.7z')

RubyLzma::Archive::Reader.open_buffer(archive_data) do |reader|
  reader.entries.each_with_index do |entry, i|
    next unless entry.name.end_with?('.log')
    
    # Extract log file to memory
    log_content = reader.extract_data(i)
    
    # Process line by line
    log_content.each_line do |line|
      # Parse and analyze
      if line.include?('ERROR')
        puts "Error found in #{entry.name}: #{line.strip}"
      end
    end
  end
end
```

## Advanced Usage

### Entry Metadata

```ruby
require 'ruby_lzma'

RubyLzma::Archive::Reader.open('archive.7z') do |reader|
  reader.entries.each do |entry|
    puts "Entry: #{entry.name}"
    puts "  Size: #{entry.size} bytes"
    puts "  Compressed: #{entry.compressed_size} bytes"
    puts "  Ratio: #{'%.1f' % (100.0 * entry.compressed_size / entry.size)}%"
    puts "  CRC32: 0x#{entry.crc.to_s(16).upcase}"
    puts "  Modified: #{entry.mtime}"
    puts "  Attributes: 0x#{entry.attributes.to_s(16)}"
    puts "  Type: #{entry.directory? ? 'Directory' : 'File'}"
    puts
  end
end
```

### Verify Before Extraction

```ruby
require 'ruby_lzma'

def extract_safely(archive_path, output_dir, password: nil)
  RubyLzma::Archive::Reader.open(archive_path, password: password) do |reader|
    # Verify archive integrity
    unless reader.test
      raise "Archive verification failed - corrupt or wrong password"
    end
    
    # Check available disk space
    total_size = reader.entries.reject(&:directory?).sum(&:size)
    stat = File.statvfs(output_dir)
    available = stat.f_bavail * stat.f_bsize
    
    if total_size > available
      raise "Insufficient disk space: need #{total_size} bytes, have #{available} bytes"
    end
    
    # Extract
    reader.extract_all(output_dir)
    puts "Successfully extracted #{reader.size} entries"
  end
end

extract_safely('large_archive.7z', '/output', password: 'secret')
```

### Concurrent Processing

```ruby
require 'ruby_lzma'
require 'concurrent'

archive_data = File.binread('archive.7z')

# Read entry list from single reader
entries = []
RubyLzma::Archive::Reader.open_buffer(archive_data) do |reader|
  entries = reader.entries.to_a
end

# Process entries concurrently
pool = Concurrent::FixedThreadPool.new(4)

entries.each_with_index do |entry, i|
  pool.post do
    # Each thread creates its own reader from the same data
    RubyLzma::Archive::Reader.open_buffer(archive_data) do |reader|
      data = reader.extract_data(i)
      
      # Process data
      processed = process_file(data, entry.name)
      
      # Save result
      output_path = File.join('/output', entry.name)
      File.binwrite(output_path, processed)
    end
  end
end

pool.shutdown
pool.wait_for_termination
```

## Error Handling

### Comprehensive Error Handling

```ruby
require 'ruby_lzma'

def safe_extract(archive_path, output_dir, password: nil)
  reader = nil
  
  begin
    reader = RubyLzma::Archive::Reader.new(archive_path, password: password)
    
    # Verify
    unless reader.test
      puts "Warning: Archive verification failed"
      return false
    end
    
    # Extract
    reader.extract_all(output_dir)
    puts "Successfully extracted to #{output_dir}"
    true
    
  rescue Errno::ENOENT => e
    puts "File not found: #{e.message}"
    false
    
  rescue RubyLzma::Error => e
    puts "Archive error: #{e.message}"
    false
    
  rescue StandardError => e
    puts "Unexpected error: #{e.message}"
    puts e.backtrace.first(3)
    false
    
  ensure
    reader&.close
  end
end

safe_extract('archive.7z', '/output', password: 'secret')
```

## Additional Resources

- [README.md](README.md) - Main documentation
- [SDK_UPDATE.md](SDK_UPDATE.md) - SDK update guide
- [CHANGELOG.md](CHANGELOG.md) - Version history
- [sig/ruby_lzma.rbs](sig/ruby_lzma.rbs) - Type signatures
