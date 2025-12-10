# Test: can we compile everything and let the linker strip?
require "mkmf"

platform = :macos
$CXXFLAGS << " -std=c++11 -stdlib=libc++ -fPIC -O2 -Wall"
$CFLAGS << " -fPIC -O2 -Wall"
$LDFLAGS << " -stdlib=libc++"

# Dead code elimination
$CXXFLAGS << " -ffunction-sections -fdata-sections"
$CFLAGS << " -ffunction-sections -fdata-sections"
$LDFLAGS << " -Wl,-dead_strip"

$CXXFLAGS << " -DZ7_EXTRACT_ONLY -DZ7_ST"
$CFLAGS << " -DZ7_ST"

$INCFLAGS << " -I$(srcdir) -I$(srcdir)/lzma_sdk/C -I$(srcdir)/lzma_sdk/CPP"

# Try to include ALL Windows files (no whitelist)
all_windows = Dir.glob("lzma_sdk/CPP/Windows/*.cpp")
puts "Windows files found: #{all_windows.size}"
all_windows.each { |f| puts "  #{File.basename(f)}" }

# Check for files that need Windows-only headers
require 'open3'
all_windows.each do |file|
  content = File.read(file)
  if content.match?(/<ShlObj\.h>|<CommCtrl\.h>|<ShellAPI\.h>/)
    puts "SKIP: #{File.basename(file)} needs Windows-only headers"
  end
end
