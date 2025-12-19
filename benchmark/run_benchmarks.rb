#!/usr/bin/env ruby
# Benchmark comparison: ruby_lzma vs seven_zip_ruby vs 7z CLI

require 'benchmark'
require 'fileutils'
require 'stringio'
require_relative '../lib/ruby_lzma'

# Try to load seven_zip_ruby for comparison
begin
  require 'seven_zip_ruby'
  SEVEN_ZIP_RUBY_AVAILABLE = true
rescue LoadError
  SEVEN_ZIP_RUBY_AVAILABLE = false
end

BENCHMARK_DIR = File.expand_path('../', __FILE__)
FIXTURES_DIR = File.join(BENCHMARK_DIR, 'fixtures')
OUTPUT_DIR = File.join(BENCHMARK_DIR, 'output')
RESULTS_FILE = File.join(BENCHMARK_DIR, 'results.txt')

# Test configurations
# Note: larger archives (medium+) take a very long time for extract_to_memory benchmarks
# because the current implementation opens the archive fresh for each file.
# Use ENV['BENCHMARK_ALL'] to include larger archives.
ARCHIVE_CONFIGS = if ENV['BENCHMARK_ALL']
  [
    { name: 'tiny', password: nil },
    { name: 'tiny', password: 'benchmark123' },
    { name: 'small', password: nil },
    { name: 'small', password: 'benchmark123' },
    { name: 'medium', password: nil },
    { name: 'medium', password: 'benchmark123' }
  ]
else
  [
    { name: 'tiny', password: nil },
    { name: 'tiny', password: 'benchmark123' },
    { name: 'small', password: nil },
    { name: 'small', password: 'benchmark123' }
  ]
end

class BenchmarkRunner
  def initialize
    @results = []
    FileUtils.mkdir_p(OUTPUT_DIR)
  end

  def format_time(seconds)
    if seconds < 0.001
      "#{(seconds * 1_000_000).round(0)} μs"
    elsif seconds < 1
      "#{(seconds * 1000).round(1)} ms"
    else
      "#{seconds.round(3)} s"
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

  def get_archive_path(config)
    filename = config[:password] ? "#{config[:name]}_encrypted.7z" : "#{config[:name]}.7z"
    File.join(FIXTURES_DIR, filename)
  end

  def benchmark_operation(name, &block)
    GC.start  # Clean up before benchmark
    result = Benchmark.measure(&block)
    result.real
  end

  # Benchmark: List entries
  def benchmark_list_entries(archive_path, password)
    puts "    List entries..."

    # Our library
    our_time = benchmark_operation("list_ruby") do
      RubyLzma::Archive::Reader.open(archive_path, password: password) do |reader|
        count = reader.entries.size
      end
    end

    # seven_zip_ruby gem (if available)
    szr_time = nil
    if SEVEN_ZIP_RUBY_AVAILABLE
      begin
        szr_time = benchmark_operation("list_szr") do
          File.open(archive_path, 'rb') do |file|
            SevenZipRuby::Reader.open(file, password: password) do |reader|
              count = reader.entries.size
            end
          end
        end
      rescue => e
        puts "      (seven_zip_ruby failed: #{e.message})"
        szr_time = :failed
      end
    end

    # 7z CLI
    cli_time = benchmark_operation("list_7z") do
      cmd = ['7z', 'l', '-slt']
      cmd += ["-p#{password}"] if password
      cmd << archive_path
      `#{cmd.join(' ')} 2>/dev/null`
    end

    speedup_vs_cli = cli_time / our_time
    speedup_vs_szr = (szr_time && szr_time != :failed) ? (szr_time / our_time) : nil

    {
      operation: 'List entries',
      our_time: our_time,
      szr_time: szr_time,
      cli_time: cli_time,
      speedup_vs_cli: speedup_vs_cli,
      speedup_vs_szr: speedup_vs_szr
    }
  end

  # Benchmark: Verify archive
  def benchmark_verify(archive_path, password)
    puts "    Verify archive..."

    # Our library
    our_time = benchmark_operation("verify_ruby") do
      RubyLzma::Archive::Reader.open(archive_path, password: password) do |reader|
        reader.test
      end
    end

    # seven_zip_ruby gem (if available)
    szr_time = nil
    if SEVEN_ZIP_RUBY_AVAILABLE
      begin
        szr_time = benchmark_operation("verify_szr") do
          File.open(archive_path, 'rb') do |file|
            SevenZipRuby::Reader.open(file, password: password) do |reader|
              reader.test
            end
          end
        end
      rescue => e
        puts "      (seven_zip_ruby failed: #{e.message})"
        szr_time = :failed
      end
    end

    # 7z CLI
    cli_time = benchmark_operation("verify_7z") do
      cmd = ['7z', 't']
      cmd += ["-p#{password}"] if password
      cmd << archive_path
      system(*cmd, out: '/dev/null', err: '/dev/null')
    end

    speedup_vs_cli = cli_time / our_time
    speedup_vs_szr = (szr_time && szr_time != :failed) ? (szr_time / our_time) : nil

    {
      operation: 'Verify',
      our_time: our_time,
      szr_time: szr_time,
      cli_time: cli_time,
      speedup_vs_cli: speedup_vs_cli,
      speedup_vs_szr: speedup_vs_szr
    }
  end

  # Benchmark: Extract to files
  def benchmark_extract_files(archive_path, password)
    puts "    Extract to files..."

    output_ruby = File.join(OUTPUT_DIR, 'ruby_extract')
    output_szr = File.join(OUTPUT_DIR, 'szr_extract')
    output_cli = File.join(OUTPUT_DIR, 'cli_extract')

    # Our library
    FileUtils.rm_rf(output_ruby)
    FileUtils.mkdir_p(output_ruby)
    our_time = benchmark_operation("extract_ruby") do
      RubyLzma::Archive::Reader.open(archive_path, password: password) do |reader|
        reader.extract_all(output_ruby)
      end
    end

    # seven_zip_ruby gem (if available)
    szr_time = nil
    if SEVEN_ZIP_RUBY_AVAILABLE
      begin
        FileUtils.rm_rf(output_szr)
        FileUtils.mkdir_p(output_szr)
        szr_time = benchmark_operation("extract_szr") do
          File.open(archive_path, 'rb') do |file|
            SevenZipRuby::Reader.open(file, password: password) do |reader|
              reader.entries.each do |entry|
                next if entry.directory?
                output_path = File.join(output_szr, entry.path)
                FileUtils.mkdir_p(File.dirname(output_path))
                reader.extract(entry, output_path)
              end
            end
          end
        end
      rescue => e
        puts "      (seven_zip_ruby failed: #{e.message})"
        szr_time = :failed
      end
    end

    # 7z CLI
    FileUtils.rm_rf(output_cli)
    FileUtils.mkdir_p(output_cli)
    cli_time = benchmark_operation("extract_7z") do
      cmd = ['7z', 'x', "-o#{output_cli}"]
      cmd += ["-p#{password}"] if password
      cmd << archive_path
      system(*cmd, out: '/dev/null', err: '/dev/null')
    end

    speedup_vs_cli = cli_time / our_time
    speedup_vs_szr = (szr_time && szr_time != :failed) ? (szr_time / our_time) : nil

    {
      operation: 'Extract to files',
      our_time: our_time,
      szr_time: szr_time,
      cli_time: cli_time,
      speedup_vs_cli: speedup_vs_cli,
      speedup_vs_szr: speedup_vs_szr
    }
  end

  # Benchmark: Extract to memory
  def benchmark_extract_memory(archive_path, password)
    puts "    Extract to memory..."
    
    # Our library
    our_time = benchmark_operation("extract_memory_ruby") do
      RubyLzma::Archive::Reader.open(archive_path, password: password) do |reader|
        reader.entries.each_with_index do |entry, i|
          next if entry.directory?
          data = reader.extract_data(i)
        end
      end
    end
    
    # 7z CLI (extract to stdout, capture in memory)
    cli_time = benchmark_operation("extract_memory_7z") do
      RubyLzma::Archive::Reader.open(archive_path, password: password) do |reader|
        reader.entries.each do |entry|
          next if entry.directory?
          cmd = ['7z', 'e', '-so']
          cmd += ["-p#{password}"] if password
          cmd << archive_path
          cmd << entry.name
          output = `#{cmd.join(' ')} 2>/dev/null`
        end
      end
    end
    
    speedup_vs_cli = cli_time / our_time
    {
      operation: 'Extract to memory',
      our_time: our_time,
      szr_time: nil,
      cli_time: cli_time,
      speedup_vs_cli: speedup_vs_cli,
      speedup_vs_szr: nil
    }
  end

  # Benchmark: Open from memory (StringIO)
  def benchmark_open_memory(archive_path, password)
    puts "    Open from memory..."
    
    # Load archive into memory once
    archive_data = File.binread(archive_path)
    
    # Our library (StringIO)
    our_time = benchmark_operation("open_memory_ruby") do
      RubyLzma::Archive::Reader.open_buffer(StringIO.new(archive_data), password: password) do |reader|
        count = reader.entries.size
      end
    end
    
    # 7z CLI (write to temp file, then open)
    cli_time = benchmark_operation("open_memory_7z") do
      temp_file = File.join(OUTPUT_DIR, 'temp_archive.7z')
      File.binwrite(temp_file, archive_data)
      cmd = ['7z', 'l']
      cmd += ["-p#{password}"] if password
      cmd << temp_file
      `#{cmd.join(' ')} 2>/dev/null`
      File.delete(temp_file)
    end
    
    speedup_vs_cli = cli_time / our_time
    {
      operation: 'Open from memory',
      our_time: our_time,
      szr_time: nil,
      cli_time: cli_time,
      speedup_vs_cli: speedup_vs_cli,
      speedup_vs_szr: nil
    }
  end

  def run_benchmark_suite(config)
    archive_path = get_archive_path(config)
    
    unless File.exist?(archive_path)
      puts "  ⚠ Archive not found: #{File.basename(archive_path)}"
      return
    end
    
    archive_size = File.size(archive_path)
    password = config[:password]
    
    puts "\n" + "=" * 70
    puts "Benchmarking: #{File.basename(archive_path)}"
    puts "  Size: #{format_bytes(archive_size)}"
    puts "  Password: #{password ? 'Yes' : 'No'}"
    puts "=" * 70
    
    suite_results = []
    
    # Run all benchmarks
    suite_results << benchmark_list_entries(archive_path, password)
    suite_results << benchmark_verify(archive_path, password)
    suite_results << benchmark_extract_files(archive_path, password)
    suite_results << benchmark_extract_memory(archive_path, password)
    suite_results << benchmark_open_memory(archive_path, password)
    
    # Print results table
    has_original_comparison = suite_results.any? { |r| r[:szr_time] }

    if has_original_comparison && SEVEN_ZIP_RUBY_AVAILABLE
      puts "\n  Results (with seven_zip_ruby comparison):"
      puts "  " + "-" * 90
      puts "  #{'Operation'.ljust(20)} #{'ruby_lzma'.rjust(10)} #{'szr'.rjust(10)} #{'7z CLI'.rjust(10)} #{'vs szr'.rjust(12)} #{'vs CLI'.rjust(12)}"
      puts "  " + "-" * 90

      suite_results.each do |result|
        line = "  #{result[:operation].ljust(20)} #{format_time(result[:our_time]).rjust(10)} "

        if result[:szr_time] == :failed
          line += "#{'DNF'.rjust(10)} "
          speedup_orig_str = "DNF"
        elsif result[:szr_time]
          speedup_orig_str = if result[:speedup_vs_szr] >= 1.0
            "#{result[:speedup_vs_szr].round(2)}x ⭐"
          else
            "#{(1.0 / result[:speedup_vs_szr]).round(2)}x"
          end
          line += "#{format_time(result[:szr_time]).rjust(10)} "
        else
          line += "#{'N/A'.rjust(10)} "
          speedup_orig_str = "N/A"
        end

        speedup_cli_str = if result[:speedup_vs_cli] >= 1.0
          "#{result[:speedup_vs_cli].round(2)}x"
        else
          "#{(1.0 / result[:speedup_vs_cli]).round(2)}x"
        end

        line += "#{format_time(result[:cli_time]).rjust(10)} "
        line += "#{speedup_orig_str.rjust(12)} "
        line += "#{speedup_cli_str.rjust(12)}"

        puts line
      end
    else
      puts "\n  Results:"
      puts "  " + "-" * 66
      puts "  #{'Operation'.ljust(25)} #{'ruby_lzma'.rjust(12)} #{'7z CLI'.rjust(12)} #{'Speedup'.rjust(12)}"
      puts "  " + "-" * 66

      suite_results.each do |result|
        # Handle both old and new result structures
        speedup = result[:speedup_vs_cli] || result[:speedup]
        speedup_str = if speedup >= 1.0
          "#{speedup.round(2)}x faster"
        else
          "#{(1.0 / speedup).round(2)}x slower"
        end

        puts "  #{result[:operation].ljust(25)} " \
             "#{format_time(result[:our_time]).rjust(12)} " \
             "#{format_time(result[:cli_time]).rjust(12)} " \
             "#{speedup_str.rjust(12)}"
      end
    end
    
    @results << {
      archive: File.basename(archive_path),
      size: archive_size,
      password: !!password,
      results: suite_results
    }
  end

  def save_results
    File.open(RESULTS_FILE, 'w') do |f|
      f.puts "7-Zip Benchmark Results"
      f.puts "=" * 70
      f.puts "Date: #{Time.now}"
      f.puts "Ruby Library: ruby_lzma #{RubyLzma::VERSION}"
      f.puts "LZMA SDK: #{RubyLzma.sdk_version}"
      f.puts "\n"

      @results.each do |suite|
        f.puts "\nArchive: #{suite[:archive]} (#{format_bytes(suite[:size])})"
        f.puts "Password: #{suite[:password] ? 'Yes' : 'No'}"
        f.puts "-" * 70

        suite[:results].each do |result|
          line = "#{result[:operation].ljust(25)}: "
          line += "ruby_lzma=#{format_time(result[:our_time]).rjust(10)}, "

          # Add szr comparison if available
          if result[:szr_time]
            if result[:szr_time] == :failed
              line += "szr=DNF, "
            else
              line += "szr=#{format_time(result[:szr_time]).rjust(10)}, "
            end
          end

          line += "CLI=#{format_time(result[:cli_time]).rjust(10)}, "

          # Add speedups
          speedup_cli = result[:speedup_vs_cli] || result[:speedup]
          line += "vs CLI=#{speedup_cli.round(2)}x"

          if result[:speedup_vs_szr]
            line += ", vs szr=#{result[:speedup_vs_szr].round(2)}x"
          elsif result[:szr_time] == :failed
            line += ", vs szr=DNF"
          end

          f.puts line
        end
      end
    end

    puts "\n\n✓ Results saved to: #{RESULTS_FILE}"
  end

  def run_all
    # Check prerequisites
    unless system('which 7z > /dev/null 2>&1')
      puts "ERROR: 7z command not found! Install with: brew install p7zip"
      exit 1
    end
    
    puts "7-Zip Performance Benchmark"
    puts "Comparing: ruby_lzma vs 7z CLI"
    puts ""
    
    # Run benchmarks for each configuration
    ARCHIVE_CONFIGS.each do |config|
      run_benchmark_suite(config)
    end
    
    # Save results
    save_results
    
    # Cleanup
    FileUtils.rm_rf(OUTPUT_DIR)
    
    puts "\n" + "=" * 70
    puts "Benchmark completed!"
    puts "=" * 70
  end
end

# Run benchmarks
runner = BenchmarkRunner.new
runner.run_all
