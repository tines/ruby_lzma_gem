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
require_relative "/workspace/lib/ruby_lzma"

archive = ARGV[0]

puts "Running memory leak tests..."

# Test 1: Open and close
10.times do
  reader = RubyLzma::Archive::Reader.new(archive)
  reader.close
end
puts "  Test 1: Open/Close - done"

# Test 2: Extract to memory
RubyLzma::Archive::Reader.open(archive) do |reader|
  reader.entries.first(5).each_with_index do |entry, i|
    next if entry.directory?
    data = reader.extract_data(i)
  end
end
puts "  Test 2: Extract to memory - done"

# Test 3: Verify
RubyLzma::Archive::Reader.open(archive) do |reader|
  reader.test
end
puts "  Test 3: Verify - done"

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
