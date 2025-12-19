#!/usr/bin/env ruby
# Generate test archives of various sizes for benchmarking

require 'fileutils'

BENCHMARK_DIR = File.expand_path('../', __FILE__)
FIXTURES_DIR = File.join(BENCHMARK_DIR, 'fixtures')
DATA_DIR = File.join(FIXTURES_DIR, 'data')

# Test configurations
TEST_SIZES = {
  'tiny'   => { files: 10, size_per_file: 1024 },           # 10KB total
  'small'  => { files: 50, size_per_file: 10 * 1024 },      # 500KB total
  'medium' => { files: 100, size_per_file: 100 * 1024 },    # 10MB total
  'large'  => { files: 500, size_per_file: 100 * 1024 },    # 50MB total
  'xlarge' => { files: 1000, size_per_file: 100 * 1024 }    # 100MB total
}

def generate_random_data(size)
  # Generate compressible data (mix of random and repetitive)
  data = ""
  
  # 50% repetitive patterns (compresses well)
  (size / 2 / 100).times do
    data << ("Lorem ipsum dolor sit amet, consectetur adipiscing elit. " * 10)[0..99]
  end
  
  # 50% random data (compresses poorly)
  data << Random.bytes(size / 2)
  
  data[0...size]
end

def create_test_files(config_name, config)
  puts "\n=== Generating #{config_name} test set ==="
  
  test_dir = File.join(DATA_DIR, config_name)
  FileUtils.rm_rf(test_dir)
  FileUtils.mkdir_p(test_dir)
  
  # Create subdirectories
  subdirs = ['documents', 'images', 'logs', 'data']
  subdirs.each { |subdir| FileUtils.mkdir_p(File.join(test_dir, subdir)) }
  
  files_created = []
  config[:files].times do |i|
    subdir = subdirs[i % subdirs.size]
    filename = File.join(test_dir, subdir, "file_#{i.to_s.rjust(4, '0')}.dat")
    
    File.binwrite(filename, generate_random_data(config[:size_per_file]))
    files_created << filename
  end
  
  total_size = files_created.sum { |f| File.size(f) }
  puts "  Created #{files_created.size} files"
  puts "  Total uncompressed size: #{format_bytes(total_size)}"
  
  test_dir
end

def create_archive(test_dir, config_name, password: nil)
  archive_name = password ? "#{config_name}_encrypted.7z" : "#{config_name}.7z"
  archive_path = File.join(FIXTURES_DIR, archive_name)
  
  # Remove existing archive
  FileUtils.rm_f(archive_path)
  
  # Create archive with 7z CLI
  cmd_parts = ['7z', 'a', '-t7z', '-mx=5']  # Normal compression
  cmd_parts << "-p#{password}" if password
  cmd_parts << archive_path
  cmd_parts << File.join(test_dir, '*')
  
  print "  Creating #{archive_name}... "
  result = system(*cmd_parts, out: '/dev/null', err: '/dev/null')
  
  if result && File.exist?(archive_path)
    compressed_size = File.size(archive_path)
    puts "✓ (#{format_bytes(compressed_size)})"
    archive_path
  else
    puts "✗ Failed"
    nil
  end
end

def format_bytes(bytes)
  if bytes < 1024
    "#{bytes} B"
  elsif bytes < 1024 * 1024
    "#{(bytes / 1024.0).round(1)} KB"
  else
    "#{(bytes / 1024.0 / 1024.0).round(1)} MB"
  end
end

# Main execution
puts "=" * 60
puts "7-Zip Archive Generator for Benchmarking"
puts "=" * 60

# Check if 7z is available
unless system('which 7z > /dev/null 2>&1')
  puts "\nERROR: 7z command not found!"
  puts "Install with: brew install p7zip"
  exit 1
end

# Create directories
FileUtils.mkdir_p(FIXTURES_DIR)
FileUtils.mkdir_p(DATA_DIR)

# Generate archives
archives_created = []

TEST_SIZES.each do |name, config|
  # Create test files
  test_dir = create_test_files(name, config)
  
  # Create unencrypted archive
  archive = create_archive(test_dir, name)
  archives_created << archive if archive
  
  # Create encrypted archive
  archive = create_archive(test_dir, name, password: 'benchmark123')
  archives_created << archive if archive
end

# Summary
puts "\n" + "=" * 60
puts "Summary"
puts "=" * 60
puts "Archives created: #{archives_created.size}"

archives_created.each do |path|
  size = File.size(path)
  puts "  #{File.basename(path).ljust(30)} #{format_bytes(size)}"
end

puts "\nFixtures directory: #{FIXTURES_DIR}"
puts "✓ Test archives ready for benchmarking"
