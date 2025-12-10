#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Basic usage of RubyLzma gem

require "bundler/setup"
require "ruby_lzma"

# Create a test archive path
archive_path = File.join(__dir__, "..", "spec", "fixtures", "test.7z")

puts "RubyLzma - Basic Usage Example"
puts "=" * 50
puts

# Example 1: Open and list entries
puts "Example 1: Opening an archive and listing entries"
puts "-" * 50

RubyLzma::Archive::Reader.open(archive_path) do |archive|
  puts "Archive: #{archive.path}"
  puts "Total entries: #{archive.size}"
  puts

  archive.entries.each do |entry|
    type = entry.directory? ? "[DIR]" : "[FILE]"
    size_str = entry.file? ? " (#{entry.size} bytes)" : ""
    puts "  #{type} #{entry.name}#{size_str}"
  end
end

puts
puts

# Example 2: Iterate using Enumerable methods
puts "Example 2: Using Enumerable methods"
puts "-" * 50

reader = RubyLzma::Archive::Reader.new(archive_path)

# Count files and directories
file_count = reader.count(&:file?)
dir_count = reader.count(&:directory?)

puts "Files: #{file_count}"
puts "Directories: #{dir_count}"
puts

# Find files larger than 15 bytes
large_files = reader.select { |e| e.file? && e.size > 15 }
puts "Files larger than 15 bytes:"
large_files.each do |file|
  puts "  - #{file.name} (#{file.size} bytes)"
end

reader.close

puts
puts

# Example 3: Extract files
puts "Example 3: Extracting files"
puts "-" * 50

output_dir = File.join(__dir__, "output")
FileUtils.rm_rf(output_dir)
FileUtils.mkdir_p(output_dir)

RubyLzma::Archive::Reader.open(archive_path) do |archive|
  # Extract first file
  file_entry = archive.entries.find(&:file?)
  if file_entry
    output_path = File.join(output_dir, File.basename(file_entry.name))
    archive.extract(file_entry, output_path)
    puts "Extracted: #{file_entry.name} -> #{output_path}"
    puts "Content: #{File.read(output_path).inspect}"
  end
end

puts
puts

# Example 4: Extract all files
puts "Example 4: Extracting all files"
puts "-" * 50

extract_dir = File.join(__dir__, "extracted")
FileUtils.rm_rf(extract_dir)

RubyLzma::Archive::Reader.open(archive_path) do |archive|
  archive.extract_all(extract_dir)
  puts "Extracted all files to: #{extract_dir}"

  # List extracted files
  extracted = Dir.glob("#{extract_dir}/**/*").select { |f| File.file?(f) }
  puts "Extracted #{extracted.size} file(s):"
  extracted.each do |file|
    puts "  - #{file}"
  end
end

puts
puts "=" * 50
puts "Examples complete!"
