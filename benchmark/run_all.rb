#!/usr/bin/env ruby
# Master script to run all benchmarks and tests

require 'fileutils'

BENCHMARK_DIR = File.expand_path('../', __FILE__)

def run_command(description, command)
  puts "\n" + "=" * 70
  puts description
  puts "=" * 70
  puts "Command: #{command}"
  puts ""
  
  success = system(command)
  
  if success
    puts "\n✓ #{description} completed successfully"
  else
    puts "\n✗ #{description} failed"
    exit 1 unless ENV['CONTINUE_ON_ERROR']
  end
  
  success
end

def check_prerequisites
  puts "Checking prerequisites..."
  
  missing = []
  
  # Check for 7z
  unless system('which 7z > /dev/null 2>&1')
    missing << "7z (install with: brew install p7zip)"
  end
  
  if missing.any?
    puts "\n✗ Missing prerequisites:"
    missing.each { |item| puts "  - #{item}" }
    puts "\nPlease install missing tools and try again."
    exit 1
  end
  
  puts "✓ All prerequisites found"
end

puts <<~BANNER
  ╔══════════════════════════════════════════════════════════════════════╗
  ║                                                                      ║
  ║              RubyLzma Benchmark Suite                                ║
  ║                                                                      ║
  ║  This will run:                                                      ║
  ║    1. Test archive generation                                        ║
  ║    2. Performance benchmarks (vs 7z CLI)                             ║
  ║    3. Memory leak detection                                          ║
  ║    4. Detailed memory profiling (if memory_profiler gem available)   ║
  ║                                                                      ║
  ║  Estimated time: 5-10 minutes                                        ║
  ║                                                                      ║
  ╚══════════════════════════════════════════════════════════════════════╝

BANNER

# Check prerequisites
check_prerequisites

# 1. Generate test archives
run_command(
  "Step 1: Generating test archives",
  "ruby #{File.join(BENCHMARK_DIR, 'generate_test_archives.rb')}"
)

# 2. Run performance benchmarks
run_command(
  "Step 2: Running performance benchmarks",
  "ruby #{File.join(BENCHMARK_DIR, 'run_benchmarks.rb')}"
)

# 3. Memory leak detection
run_command(
  "Step 3: Memory leak detection",
  "ruby #{File.join(BENCHMARK_DIR, 'check_memory_leaks.rb')}"
)

# 4. Detailed memory profiling (optional)
if system('gem list memory_profiler -i > /dev/null 2>&1')
  run_command(
    "Step 4: Detailed memory profiling",
    "ruby #{File.join(BENCHMARK_DIR, 'profile_memory.rb')}"
  )
else
  puts "\n" + "=" * 70
  puts "Step 4: Detailed memory profiling (SKIPPED)"
  puts "=" * 70
  puts "memory_profiler gem not installed"
  puts "Install with: gem install memory_profiler"
  puts ""
end

# Final summary
puts "\n" + "╔" + "═" * 68 + "╗"
puts "║" + " " * 68 + "║"
puts "║" + "  All Benchmarks Completed!".center(68) + "║"
puts "║" + " " * 68 + "║"
puts "╚" + "═" * 68 + "╝"

puts "\nResults saved to:"
puts "  - Performance: #{File.join(BENCHMARK_DIR, 'results.txt')}"
puts "  - Test archives: #{File.join(BENCHMARK_DIR, 'fixtures')}"

puts "\nOptional: Run C-level leak detection with Valgrind:"
puts "  ./benchmark/check_c_leaks.sh"

puts "\nTo view results:"
puts "  cat benchmark/results.txt"
