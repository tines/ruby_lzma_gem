#!/bin/bash
# Check for C-level memory leaks using Valgrind
# On macOS, runs via Docker container since Valgrind doesn't work well on Mac

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BENCHMARK_DIR="$SCRIPT_DIR"
FIXTURES_DIR="$BENCHMARK_DIR/fixtures"
TEST_ARCHIVE="$FIXTURES_DIR/small.7z"

# Detect platform
detect_platform() {
    case "$(uname -s)" in
        Darwin*)    echo "macos" ;;
        Linux*)     echo "linux" ;;
        *)          echo "unknown" ;;
    esac
}

PLATFORM=$(detect_platform)

echo "======================================================================"
echo "C-Level Memory Leak Detection (Valgrind)"
echo "======================================================================"
echo "Platform: $PLATFORM"
echo ""

# Check if test archive exists
if [ ! -f "$TEST_ARCHIVE" ]; then
    echo "ERROR: Test archive not found: $TEST_ARCHIVE"
    echo "Run: ruby benchmark/generate_test_archives.rb"
    exit 1
fi

# Create the test script content
TEST_SCRIPT_CONTENT='
require "fileutils"
require_relative "/workspace/lib/ruby_lzma"

archive = ARGV[0]
output_dir = "/tmp/valgrind_test_output"
FileUtils.mkdir_p(output_dir)

puts "Running memory leak tests..."

# ============= READER TESTS =============

# Test 1: Open and close
10.times do
  reader = RubyLzma::Archive::Reader.new(archive)
  reader.close
end
puts "  Test 1: Reader Open/Close - done"

# Test 2: Extract to memory
RubyLzma::Archive::Reader.open(archive) do |reader|
  reader.entries.first(5).each_with_index do |entry, i|
    next if entry.directory?
    data = reader.extract_data(i)
  end
end
puts "  Test 2: Reader Extract to memory - done"

# Test 3: Verify
RubyLzma::Archive::Reader.open(archive) do |reader|
  reader.test
end
puts "  Test 3: Reader Verify - done"

# ============= WRITER TESTS =============

# Test 4: Create archive with add_data
10.times do |n|
  output_archive = "#{output_dir}/test_write_#{n}.7z"
  RubyLzma::Archive::Writer.open(output_archive) do |writer|
    writer.add_data("Test data content #{n}", "file.txt")
  end
  FileUtils.rm_f(output_archive)
end
puts "  Test 4: Writer Create with add_data - done"

# Test 5: Create archive with multiple entries
5.times do |n|
  output_archive = "#{output_dir}/test_multi_#{n}.7z"
  RubyLzma::Archive::Writer.open(output_archive) do |writer|
    5.times do |i|
      writer.add_data("Content for file #{i}" * 100, "file_#{i}.txt")
    end
    writer.mkdir("empty_dir")
  end
  FileUtils.rm_f(output_archive)
end
puts "  Test 5: Writer Create multiple entries - done"

# Test 6: Create encrypted archive
5.times do |n|
  output_archive = "#{output_dir}/test_encrypted_#{n}.7z"
  RubyLzma::Archive::Writer.open(output_archive, password: "TestPassword123") do |writer|
    writer.add_data("Secret data #{n}" * 50, "secret.txt")
  end
  FileUtils.rm_f(output_archive)
end
puts "  Test 6: Writer Create encrypted - done"

# Test 7: Create large archive
3.times do |n|
  output_archive = "#{output_dir}/test_large_#{n}.7z"
  large_data = "x" * 100_000  # 100KB
  RubyLzma::Archive::Writer.open(output_archive) do |writer|
    3.times do |i|
      writer.add_data(large_data, "large_#{i}.txt")
    end
  end
  FileUtils.rm_f(output_archive)
end
puts "  Test 7: Writer Create large archive - done"

# Test 8: Writer open and close explicitly
5.times do |n|
  output_archive = "#{output_dir}/test_explicit_#{n}.7z"
  writer = RubyLzma::Archive::Writer.new(output_archive)
  writer.add_data("Test content", "test.txt")
  writer.close
  FileUtils.rm_f(output_archive)
end
puts "  Test 8: Writer explicit open/close - done"

# ============= ROUND-TRIP TEST =============

# Test 9: Write and then read back (round-trip)
3.times do |n|
  output_archive = "#{output_dir}/test_roundtrip_#{n}.7z"
  test_content = "Round trip test data #{n}" * 100

  # Write
  RubyLzma::Archive::Writer.open(output_archive) do |writer|
    writer.add_data(test_content, "roundtrip.txt")
  end

  # Read back
  RubyLzma::Archive::Reader.open(output_archive) do |reader|
    data = reader.extract_data(0)
    raise "Data mismatch!" unless data == test_content
  end

  FileUtils.rm_f(output_archive)
end
puts "  Test 9: Round-trip write/read - done"

FileUtils.rm_rf(output_dir)
puts "All tests completed successfully"
'

run_with_docker() {
    echo "Running Valgrind via Docker container..."
    echo ""
    
    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        echo "ERROR: Docker not found"
        echo "Install Docker Desktop from: https://www.docker.com/products/docker-desktop"
        exit 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        echo "ERROR: Docker daemon is not running"
        echo "Please start Docker Desktop and try again"
        exit 1
    fi
    
    # Create test script in project
    echo "$TEST_SCRIPT_CONTENT" > "$BENCHMARK_DIR/valgrind_test.rb"
    
    # Build a simple Dockerfile for running Valgrind with Ruby
    DOCKERFILE_CONTENT='
FROM ruby:3.2-slim

# Install build dependencies and Valgrind
RUN apt-get update && apt-get install -y \
    build-essential \
    valgrind \
    git \
    libyaml-dev \
    && rm -rf /var/lib/apt/lists/*

# Install gems needed for testing (skip dev dependencies)
RUN gem install ffi rake rake-compiler

WORKDIR /workspace
'
    
    echo "$DOCKERFILE_CONTENT" > "$PROJECT_ROOT/.valgrind-dockerfile"
    
    echo "Building Docker image (this may take a minute on first run)..."
    docker build -t ruby-valgrind -f "$PROJECT_ROOT/.valgrind-dockerfile" "$PROJECT_ROOT" > /dev/null 2>&1
    
    echo "Compiling native extension and running Valgrind in container..."
    echo "This may take several minutes..."
    echo ""
    
    # Run everything in one container to preserve gem installation
    docker run --rm \
        -v "$PROJECT_ROOT:/workspace" \
        -w /workspace \
        ruby-valgrind \
        bash -c '
            set -e
            
            echo "Compiling native extension..."
            cd /workspace/ext/lzma_sdk_wrapper
            ruby extconf.rb
            make clean 2>/dev/null || true
            make
            
            echo ""
            echo "Copying compiled library..."
            mkdir -p /workspace/lib/lzma_sdk_wrapper
            cp *.so /workspace/lib/lzma_sdk_wrapper/ 2>/dev/null || true
            ls -la /workspace/lib/lzma_sdk_wrapper/
            
            echo ""
            echo "Running Valgrind memory check..."
            cd /workspace
            valgrind \
                --leak-check=full \
                --show-leak-kinds=all \
                --track-origins=yes \
                --verbose \
                --log-file=/workspace/benchmark/valgrind_report.txt \
                ruby /workspace/benchmark/valgrind_test.rb /workspace/benchmark/fixtures/small.7z
        '
    
    # Cleanup
    rm -f "$PROJECT_ROOT/.valgrind-dockerfile"
    rm -f "$BENCHMARK_DIR/valgrind_test.rb"
}

run_native() {
    echo "Running Valgrind natively..."
    echo ""
    
    # Check if Valgrind is installed
    if ! command -v valgrind &> /dev/null; then
        echo "ERROR: Valgrind not found"
        echo "Install with: sudo apt-get install valgrind"
        exit 1
    fi
    
    # Create test script
    echo "$TEST_SCRIPT_CONTENT" > /tmp/valgrind_test.rb
    
    echo "Running Valgrind memory check..."
    echo "This may take several minutes..."
    echo ""
    
    # Run Valgrind
    valgrind \
        --leak-check=full \
        --show-leak-kinds=all \
        --track-origins=yes \
        --verbose \
        --log-file="$BENCHMARK_DIR/valgrind_report.txt" \
        ruby /tmp/valgrind_test.rb "$TEST_ARCHIVE"
    
    # Cleanup
    rm -f /tmp/valgrind_test.rb
}

# Run based on platform
case "$PLATFORM" in
    macos)
        run_with_docker
        ;;
    linux)
        run_native
        ;;
    *)
        echo "ERROR: Unsupported platform: $PLATFORM"
        exit 1
        ;;
esac

echo ""
echo "======================================================================"
echo "Valgrind Report Summary"
echo "======================================================================"

# Extract summary from report
if [ -f "$BENCHMARK_DIR/valgrind_report.txt" ]; then
    echo ""
    grep -A 20 "HEAP SUMMARY" "$BENCHMARK_DIR/valgrind_report.txt" || echo "No heap summary found"
    echo ""
    grep -A 10 "LEAK SUMMARY" "$BENCHMARK_DIR/valgrind_report.txt" || echo "No leak summary found"
    echo ""
    
    # Check for definite leaks
    if grep -q "definitely lost: 0 bytes" "$BENCHMARK_DIR/valgrind_report.txt"; then
        echo "✓ No definite memory leaks detected"
    else
        echo "⚠ Memory leaks detected - see full report"
    fi
    
    echo ""
    echo "Full report saved to: $BENCHMARK_DIR/valgrind_report.txt"
else
    echo "ERROR: Valgrind report not generated"
fi

echo ""
echo "Note: Some 'still reachable' memory is normal for Ruby VM"
echo "Focus on 'definitely lost' and 'indirectly lost' leaks"
