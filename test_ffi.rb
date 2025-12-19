#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple smoke test for FFI bindings

$LOAD_PATH.unshift File.expand_path("lib", __dir__)
require "ruby_lzma"

puts "Testing FFI bindings..."
puts

# Test 1: Check library loaded
puts "✓ FFI library loaded successfully"
puts "  Constants: #{RubyLzma::FFI::Constants.constants.size}"
puts "  Functions: #{RubyLzma::FFI::Library.methods(false).grep(/^sz_/).size}"
puts

# Test 2: Try to open an archive
archive_path = File.expand_path("tmp/test.7z", __dir__)

unless File.exist?(archive_path)
  puts "✗ Test archive not found at: #{archive_path}"
  puts "  Run: 7z a tmp/test.7z tmp/test_data/"
  exit 1
end

puts "Testing archive: #{archive_path}"

# Allocate error code pointer
error_ptr = RubyLzma::FFI::Library.error_pointer

# Open archive (SZ_FORMAT_7Z = 0)
handle = RubyLzma::FFI::Library.sz_open_archive(
  archive_path,
  RubyLzma::FFI::Constants::SZ_FORMAT_7Z,
  error_ptr
)

error_code = error_ptr.read_int

if error_code != RubyLzma::FFI::Constants::SZW_OK
  puts "✗ Failed to open archive: error code #{error_code}"
  exit 1
end

if handle.null?
  puts "✗ Archive handle is null"
  exit 1
end

puts "✓ Archive opened successfully"

# Get entry count
entry_count = RubyLzma::FFI::Library.sz_get_entry_count(handle)
puts "✓ Archive has #{entry_count} entries"
puts

# List entries
entry_count.times do |i|
  entry_info = RubyLzma::FFI::Types::EntryInfo.new
  result = RubyLzma::FFI::Library.sz_get_entry_info(handle, i, entry_info)

  if result != RubyLzma::FFI::Constants::SZW_OK
    puts "✗ Failed to get entry #{i} info: error code #{result}"
    next
  end

  type = entry_info.directory? ? "DIR " : "FILE"
  size = entry_info.size
  name = entry_info.name

  puts "  [#{i}] #{type} #{name} (#{size} bytes)"
end

# Close archive
close_result = RubyLzma::FFI::Library.sz_close_archive(handle)

if close_result == RubyLzma::FFI::Constants::SZW_OK
  puts
  puts "✓ Archive closed successfully"
else
  puts
  puts "✗ Failed to close archive: error code #{close_result}"
  exit 1
end

puts
puts "All tests passed! ✓"
