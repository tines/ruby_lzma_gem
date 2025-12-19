#!/usr/bin/env ruby
# Memory leak detection for ruby_lzma

require 'objspace'
require 'stringio'
require_relative '../lib/ruby_lzma'

BENCHMARK_DIR = File.expand_path('../', __FILE__)
FIXTURES_DIR = File.join(BENCHMARK_DIR, 'fixtures')

class MemoryLeakDetector
  LEAK_THRESHOLD_KB = 100  # Consider > 100KB growth per iteration as a leak
  ITERATIONS = 50

  def initialize
    @results = []
  end

  def format_bytes(bytes)
    if bytes < 1024
      "#{bytes} B"
    elsif bytes < 1024 * 1024
      "#{(bytes / 1024.0).round(1)} KB"
    else
      "#{(bytes / 1024.0 / 1024.0).round(2)} MB"
    end
  end

  def get_memory_usage
    # Force garbage collection
    GC.start
    
    # Get process memory (macOS specific)
    pid = Process.pid
    output = `ps -o rss= -p #{pid}`.strip
    output.to_i * 1024  # Convert KB to bytes
  end

  def get_object_counts
    GC.start
    counts = ObjectSpace.count_objects
    {
      total: counts[:TOTAL],
      free: counts[:FREE],
      strings: ObjectSpace.each_object(String).count,
      arrays: ObjectSpace.each_object(Array).count,
      hashes: ObjectSpace.each_object(Hash).count
    }
  end

  def test_operation(name, archive_path, password, &block)
    puts "\n" + "=" * 70
    puts "Testing: #{name}"
    puts "Archive: #{File.basename(archive_path)}"
    puts "=" * 70
    
    # Initial measurements
    initial_memory = get_memory_usage
    initial_objects = get_object_counts
    
    memory_samples = []
    object_samples = []
    
    # Run operation multiple times
    print "Running #{ITERATIONS} iterations: "
    ITERATIONS.times do |i|
      # Execute operation
      block.call(archive_path, password)
      
      # Sample every 10 iterations
      if i % 10 == 0
        print "."
        memory_samples << get_memory_usage
        object_samples << get_object_counts
      end
    end
    puts " done"
    
    # Final measurements
    final_memory = get_memory_usage
    final_objects = get_object_counts
    
    # Calculate growth
    memory_growth = final_memory - initial_memory
    memory_per_iter = memory_growth / ITERATIONS.to_f
    
    object_growth = final_objects[:total] - initial_objects[:total]
    object_per_iter = object_growth / ITERATIONS.to_f
    
    # Analyze memory trend
    if memory_samples.size > 2
      # Check if memory keeps growing (linear regression)
      avg_growth = (memory_samples.last - memory_samples.first) / memory_samples.size.to_f
      trend = avg_growth > 0 ? :growing : :stable
    else
      trend = :unknown
    end
    
    # Determine if leak detected
    leak_detected = memory_per_iter > (LEAK_THRESHOLD_KB * 1024)
    
    # Print results
    puts "\nResults:"
    puts "  Initial memory:  #{format_bytes(initial_memory)}"
    puts "  Final memory:    #{format_bytes(final_memory)}"
    puts "  Growth:          #{format_bytes(memory_growth)} (#{format_bytes(memory_per_iter)}/iter)"
    puts "  Object growth:   #{object_growth} objects (#{object_per_iter.round(1)}/iter)"
    puts "  Trend:           #{trend}"
    puts "  Status:          #{leak_detected ? '⚠ POTENTIAL LEAK' : '✓ OK'}"
    
    if leak_detected
      puts "\n  ⚠ WARNING: Memory growing faster than threshold"
      puts "    Threshold: #{LEAK_THRESHOLD_KB} KB/iteration"
      puts "    Actual: #{(memory_per_iter / 1024).round(1)} KB/iteration"
    end
    
    # Object count details
    puts "\n  Object counts:"
    total_diff = final_objects[:total] - initial_objects[:total]
    strings_diff = final_objects[:strings] - initial_objects[:strings]
    arrays_diff = final_objects[:arrays] - initial_objects[:arrays]
    hashes_diff = final_objects[:hashes] - initial_objects[:hashes]

    puts "    Total:   #{initial_objects[:total]} → #{final_objects[:total]} (#{total_diff >= 0 ? '+' : ''}#{total_diff})"
    puts "    Strings: #{initial_objects[:strings]} → #{final_objects[:strings]} (#{strings_diff >= 0 ? '+' : ''}#{strings_diff})"
    puts "    Arrays:  #{initial_objects[:arrays]} → #{final_objects[:arrays]} (#{arrays_diff >= 0 ? '+' : ''}#{arrays_diff})"
    puts "    Hashes:  #{initial_objects[:hashes]} → #{final_objects[:hashes]} (#{hashes_diff >= 0 ? '+' : ''}#{hashes_diff})"
    
    @results << {
      name: name,
      leak_detected: leak_detected,
      memory_growth: memory_growth,
      memory_per_iter: memory_per_iter,
      object_growth: object_growth
    }
  end

  def run_all_tests
    archive_path = File.join(FIXTURES_DIR, 'small.7z')
    archive_encrypted = File.join(FIXTURES_DIR, 'small_encrypted.7z')
    
    unless File.exist?(archive_path)
      puts "ERROR: Test archive not found: #{archive_path}"
      puts "Run: ruby benchmark/generate_test_archives.rb"
      exit 1
    end
    
    puts "Memory Leak Detection"
    puts "Testing library: ruby_lzma #{RubyLzma::VERSION}"
    puts "Iterations per test: #{ITERATIONS}"
    puts ""
    
    # Test 1: Open and close archive
    test_operation("Open/Close (file)", archive_path, nil) do |path, pwd|
      reader = RubyLzma::Archive::Reader.new(path, password: pwd)
      reader.close
    end
    
    # Test 2: Open and list entries
    test_operation("Open/List entries", archive_path, nil) do |path, pwd|
      RubyLzma::Archive::Reader.open(path, password: pwd) do |reader|
        entries = reader.entries
      end
    end
    
    # Test 3: Extract to memory
    test_operation("Extract to memory", archive_path, nil) do |path, pwd|
      RubyLzma::Archive::Reader.open(path, password: pwd) do |reader|
        reader.entries.first(5).each_with_index do |entry, i|
          next if entry.directory?
          data = reader.extract_data(i)
        end
      end
    end
    
    # Test 4: Verify archive
    test_operation("Verify archive", archive_path, nil) do |path, pwd|
      RubyLzma::Archive::Reader.open(path, password: pwd) do |reader|
        result = reader.test
      end
    end
    
    # Test 5: Open from memory (StringIO)
    archive_data = File.binread(archive_path)
    test_operation("Open from StringIO", archive_path, nil) do |path, pwd|
      RubyLzma::Archive::Reader.open_buffer(StringIO.new(archive_data), password: pwd) do |reader|
        entries = reader.entries
      end
    end
    
    # Test 6: Password-protected archive
    test_operation("Password-protected", archive_encrypted, 'benchmark123') do |path, pwd|
      RubyLzma::Archive::Reader.open(path, password: pwd) do |reader|
        reader.test
        entries = reader.entries
      end
    end
    
    # Summary
    print_summary
  end

  def print_summary
    puts "\n" + "=" * 70
    puts "Summary"
    puts "=" * 70
    
    leaks_found = @results.count { |r| r[:leak_detected] }
    
    if leaks_found == 0
      puts "✓ No memory leaks detected!"
    else
      puts "⚠ #{leaks_found} potential leak(s) detected:"
      @results.select { |r| r[:leak_detected] }.each do |result|
        puts "  - #{result[:name]}: #{format_bytes(result[:memory_per_iter])}/iteration"
      end
    end
    
    puts "\nMemory growth per test:"
    @results.each do |result|
      status = result[:leak_detected] ? "⚠ " : "✓ "
      puts "  #{status}#{result[:name].ljust(30)} #{format_bytes(result[:memory_per_iter])}/iter"
    end
    
    puts "\nNotes:"
    puts "  - Threshold: #{LEAK_THRESHOLD_KB} KB/iteration"
    puts "  - Some growth is normal due to Ruby's memory management"
    puts "  - Sustained linear growth indicates a potential leak"
  end
end

# Run memory leak detection
detector = MemoryLeakDetector.new
detector.run_all_tests
