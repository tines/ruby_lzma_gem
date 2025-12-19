#!/usr/bin/env ruby
# Detailed memory profiling using memory_profiler gem

begin
  require 'memory_profiler'
rescue LoadError
  puts "ERROR: memory_profiler gem not found"
  puts "Install with: gem install memory_profiler"
  exit 1
end

require 'stringio'
require_relative '../lib/ruby_lzma'

BENCHMARK_DIR = File.expand_path('../', __FILE__)
FIXTURES_DIR = File.join(BENCHMARK_DIR, 'fixtures')

def profile_operation(name, &block)
  puts "\n" + "=" * 70
  puts "Profiling: #{name}"
  puts "=" * 70
  
  report = MemoryProfiler.report do
    block.call
  end
  
  puts "\nMemory Report:"
  puts "  Total allocated: #{report.total_allocated_memsize / 1024.0} KB"
  puts "  Total retained:  #{report.total_retained_memsize / 1024.0} KB"
  puts "  Total objects allocated: #{report.total_allocated}"
  puts "  Total objects retained:  #{report.total_retained}"
  
  # Show top allocations
  if report.total_allocated > 0
    puts "\n  Top 5 allocated locations:"
    report.allocated_memory_by_location.first(5).each_with_index do |stat, i|
      # memory_profiler returns hashes with :data and :count keys
      location = stat[:data] || stat.to_s
      bytes = stat[:count] || 0
      puts "    #{i+1}. #{(bytes / 1024.0).round(1)} KB - #{location}"
    end
  end
  
  # Show retained memory (potential leaks)
  if report.total_retained > 0
    puts "\n  ⚠ Retained objects (potential leaks):"
    report.retained_memory_by_class.first(5).each do |stat|
      # memory_profiler returns hashes with :data and :count keys
      klass = stat[:data] || stat.to_s
      bytes = stat[:count] || 0
      puts "    #{klass}: #{(bytes / 1024.0).round(1)} KB"
    end
  else
    puts "\n  ✓ No retained objects detected"
  end
  
  # Return report for further analysis
  report
end

# Test archive
archive_path = File.join(FIXTURES_DIR, 'small.7z')
archive_encrypted = File.join(FIXTURES_DIR, 'small_encrypted.7z')

unless File.exist?(archive_path)
  puts "ERROR: Test archive not found: #{archive_path}"
  puts "Run: ruby benchmark/generate_test_archives.rb"
  exit 1
end

puts "Detailed Memory Profiling"
puts "Library: ruby_lzma #{RubyLzma::VERSION}"
puts ""

# Profile different operations
reports = {}

# 1. Open and list entries
reports[:list] = profile_operation("Open and list entries") do
  RubyLzma::Archive::Reader.open(archive_path) do |reader|
    entries = reader.entries
  end
end

# 2. Extract to memory
reports[:extract] = profile_operation("Extract to memory") do
  RubyLzma::Archive::Reader.open(archive_path) do |reader|
    reader.entries.first(10).each_with_index do |entry, i|
      next if entry.directory?
      data = reader.extract_data(i)
    end
  end
end

# 3. Verify archive
reports[:verify] = profile_operation("Verify archive") do
  RubyLzma::Archive::Reader.open(archive_path) do |reader|
    result = reader.test
  end
end

# 4. Open from StringIO
archive_data = File.binread(archive_path)
reports[:stringio] = profile_operation("Open from StringIO") do
  RubyLzma::Archive::Reader.open_buffer(StringIO.new(archive_data)) do |reader|
    entries = reader.entries
  end
end

# 5. Password-protected
reports[:password] = profile_operation("Password-protected archive") do
  RubyLzma::Archive::Reader.open(archive_encrypted, password: 'benchmark123') do |reader|
    reader.test
    entries = reader.entries
  end
end

# Summary
puts "\n" + "=" * 70
puts "Summary"
puts "=" * 70

total_allocated = reports.values.sum(&:total_allocated_memsize)
total_retained = reports.values.sum(&:total_retained_memsize)

puts "Total memory allocated: #{total_allocated / 1024.0 / 1024.0} MB"
puts "Total memory retained:  #{total_retained / 1024.0} KB"

if total_retained == 0
  puts "\n✓ No memory leaks detected (0 retained objects)"
else
  puts "\n⚠ Some objects retained - review reports above"
end

puts "\nPer-operation allocation:"
reports.each do |name, report|
  allocated_mb = report.total_allocated_memsize / 1024.0 / 1024.0
  retained_kb = report.total_retained_memsize / 1024.0
  
  status = report.total_retained == 0 ? "✓" : "⚠"
  puts "  #{status} #{name.to_s.ljust(15)} Alloc: #{allocated_mb.round(2)} MB, Retained: #{retained_kb.round(1)} KB"
end

puts "\nNote: memory_profiler tracks Ruby object allocations"
puts "C-level memory (7-Zip SDK) is not tracked by this tool"
puts "Use Valgrind or similar for C-level leak detection"
