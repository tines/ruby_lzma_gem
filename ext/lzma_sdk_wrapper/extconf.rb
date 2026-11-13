# frozen_string_literal: true

require "mkmf"

# Platform detection
def detect_platform
  host_os = RbConfig::CONFIG["host_os"]
  case host_os
  when /darwin|mac os/
    :macos
  when /linux/
    :linux
  when /mswin|mingw|cygwin/
    :windows
  else
    raise "Unsupported platform: #{host_os}"
  end
end

platform = detect_platform
puts "Detected platform: #{platform}"

# Set up platform-specific compiler flags
case platform
when :macos
  $CXXFLAGS << " -std=c++11 -stdlib=libc++"
  $CFLAGS << " -std=c11"
  $LDFLAGS << " -stdlib=libc++"

when :linux
  $CXXFLAGS << " -std=c++11"
  $CFLAGS << " -std=c11 -D_POSIX_C_SOURCE=200809L"
  $LDFLAGS << " -lstdc++"

when :windows
  if RbConfig::CONFIG["CC"] =~ /gcc|g\+\+/ # MinGW
    $CXXFLAGS << " -std=c++11"
    $CFLAGS << " -std=c11"
    $LDFLAGS << " -lstdc++"
  else # MSVC
    $CXXFLAGS << " /std:c++11 /EHsc"
    $LDFLAGS << " /MD"
  end
end

# Common flags for all platforms
unless platform == :windows && RbConfig::CONFIG["CC"] !~ /gcc|g\+\+/
  # Unix-like compilers (GCC/Clang/MinGW)

  # Release optimization flags
  $CXXFLAGS << " -fPIC -O3 -Wall"
  $CFLAGS << " -fPIC -O3 -Wall"

  # Disable assertions in release builds
  $CXXFLAGS << " -DNDEBUG"
  $CFLAGS << " -DNDEBUG"

  # Security hardening
  $CXXFLAGS << " -fstack-protector-strong -D_FORTIFY_SOURCE=2"
  $CFLAGS << " -fstack-protector-strong -D_FORTIFY_SOURCE=2"

  # Dead code elimination flags
  # These allow the linker to remove unused functions/data
  $CXXFLAGS << " -ffunction-sections -fdata-sections"
  $CFLAGS << " -ffunction-sections -fdata-sections"

  # Generic tuning for portable binaries (don't use -march=native for gems)
  $CXXFLAGS << " -mtune=generic"
  $CFLAGS << " -mtune=generic"

  if platform == :macos
    $LDFLAGS << " -Wl,-dead_strip"
  else
    $LDFLAGS << " -Wl,--gc-sections"
  end
else
  # MSVC
  $CXXFLAGS << " /O2 /W3"
  $CXXFLAGS << " /DNDEBUG"  # Disable assertions
  $CXXFLAGS << " /GS"       # Security: Buffer security check
  $CXXFLAGS << " /guard:cf" # Security: Control Flow Guard
  # MSVC linker dead code elimination
  $LDFLAGS << " /OPT:REF /OPT:ICF"
end

# 7-Zip SDK defines
# Note: Z7_EXTRACT_ONLY is NOT defined to enable both extraction AND compression
$CXXFLAGS << " -DZ7_ST"             # Single-threaded for simplicity
$CFLAGS << " -DZ7_ST"

# Add include directories
$INCFLAGS << " -I$(srcdir)"
$INCFLAGS << " -I$(srcdir)/lzma_sdk/C"
$INCFLAGS << " -I$(srcdir)/lzma_sdk/CPP"

# LZMA SDK source files (will be added after vendoring)
# For now, just prepare the structure
lzma_c_files = []
lzma_cpp_files = []

# Check if LZMA SDK is present
lzma_sdk_path = File.join(__dir__, "lzma_sdk")
if Dir.exist?(lzma_sdk_path)
  puts "Found LZMA SDK at: #{lzma_sdk_path}"

  # Find C files
  c_dir = File.join(lzma_sdk_path, "C")
  if Dir.exist?(c_dir)
    lzma_c_files = Dir.glob(File.join(c_dir, "*.c")).map { |f| File.basename(f) }
    puts "Found #{lzma_c_files.size} LZMA C files"
  end

  # Find CPP files (we'll need specific ones)
  cpp_dir = File.join(lzma_sdk_path, "CPP")
  if Dir.exist?(cpp_dir)
    # We'll add specific files as needed
    puts "Found LZMA CPP directory"
  end
else
  puts "Warning: LZMA SDK not found. Will need to vendor it."
  puts "Expected location: #{lzma_sdk_path}"
end

# Our wrapper source files (in current directory)
wrapper_srcs = ["lzma_sdk_wrapper.c", "cpp_bridge.cpp", "archive_callbacks.cpp"]

# LZMA SDK C source files (with full paths)
lzma_srcs = lzma_c_files.map { |f| "lzma_sdk/C/#{f}" }

# C++ files - use glob patterns to include all needed files
# This is more maintainable than manual listing
lzma_cpp_files = []

# Directories to include (all .cpp files)
include_dirs = [
  "lzma_sdk/CPP/Common",
  "lzma_sdk/CPP/7zip/Common",
  "lzma_sdk/CPP/7zip/Archive/Common",
  "lzma_sdk/CPP/7zip/Archive/7z",
  "lzma_sdk/CPP/7zip/Compress",
  "lzma_sdk/CPP/7zip/Crypto",
]

# Top-level archive exports
lzma_cpp_files += Dir.glob("lzma_sdk/CPP/7zip/Archive/*.cpp")

# All files from included directories
include_dirs.each do |dir|
  lzma_cpp_files += Dir.glob("#{dir}/*.cpp")
end

# Windows directory: Cross-platform abstraction layer (needed on ALL platforms)
# The SDK's "Windows" directory is a misnomer - it contains cross-platform abstractions
# that use #ifdef _WIN32 to provide platform-specific implementations (POSIX on Unix, Win32 on Windows).
# We MUST compile these on all platforms because:
# 1. Many SDK files include Windows headers (PropVariant.h, System.h, FileFind.h)
# 2. Our wrapper code (archive_callbacks.cpp) uses Windows file operations
# 3. The headers alone aren't enough - we need the .cpp implementations
#
# However, SOME Windows files are Windows-only (need ShlObj.h, CreateFileMapping, etc.)
# so we use a whitelist approach for cross-platform files:
windows_cross_platform = [
  "FileDir.cpp",          # Cross-platform directory operations
  "FileFind.cpp",         # Cross-platform file finding
  "FileIO.cpp",           # Cross-platform file I/O
  "FileName.cpp",         # Cross-platform filename handling
  "PropVariant.cpp",      # Cross-platform property variants
  "PropVariantConv.cpp",  # Cross-platform property conversion
  "System.cpp",           # Cross-platform system info
  "TimeUtils.cpp",        # Cross-platform time utilities
  "ErrorMsg.cpp",         # Cross-platform error messages
  "FileSystem.cpp",       # Cross-platform filesystem operations
  "SystemInfo.cpp",       # Cross-platform system information
]
windows_cross_platform.each do |file|
  lzma_cpp_files << "lzma_sdk/CPP/Windows/#{file}"
end

# Exclude patterns for UI/Bundles only
exclude_patterns = [
  %r{/UI/},        # All UI code
  %r{/Bundles/},   # Standalone applications
  %r{/Icons/},     # Icon resources
  %r{/Control/},   # GUI controls
]

# Filter out excluded files
lzma_cpp_files = lzma_cpp_files.reject do |file|
  exclude_patterns.any? { |pattern| file.match?(pattern) }
end

puts "Found #{lzma_cpp_files.size} C++ files to compile"

# Set source files
$srcs = wrapper_srcs + lzma_srcs + lzma_cpp_files

# Important: Tell mkmf where to find source files
# Automatically discover directories from our source files
vpath_dirs = $srcs.map { |f| File.dirname(f) }.uniq.sort
# Filter out current directory (.) and convert to srcdir paths
vpath_dirs = vpath_dirs.reject { |d| d == "." }
$VPATH = ["$(srcdir)"] + vpath_dirs.map { |dir| "$(srcdir)/#{dir}" }

# Debugging output
puts "Platform: #{platform}"
puts "CXXFLAGS: #{$CXXFLAGS}"
puts "CFLAGS: #{$CFLAGS}"
puts "LDFLAGS: #{$LDFLAGS}"
puts "Source files: #{$srcs.join(', ')}"

# Create Makefile
# The target name determines where the compiled library goes
create_makefile("lzma_sdk_wrapper/lzma_sdk_wrapper")

puts "\nBuild configuration:"
puts "  - Object files will be in the current directory during build"
puts "  - Final library: lzma_sdk_wrapper.bundle (or .so/.dll)"
puts "  - Use 'make clean' to remove build artifacts"
