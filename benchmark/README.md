# Benchmark Suite

This directory contains benchmarking and memory testing tools for `ruby_lzma`.

## Overview

The benchmark suite provides:
- **Performance comparison** against 7z CLI
- **Memory leak detection** (Ruby and C levels)
- **Test archive generation** for reproducible benchmarks
- **Detailed profiling** with memory_profiler

## Prerequisites

Install required tools:

```bash
# 7-Zip CLI (required for comparison)
brew install p7zip

# Memory profiler gem (optional, for detailed analysis)
gem install memory_profiler

# For C-level leak detection:
# - On macOS: Docker Desktop (Valgrind runs in container)
# - On Linux: valgrind (apt-get install valgrind)
```

## Quick Start

Run all benchmarks in one command:

```bash
# Generate test archives and run all tests
ruby benchmark/run_all.rb
```

Or run individual tests:

```bash
# 1. Generate test archives
ruby benchmark/generate_test_archives.rb

# 2. Run performance benchmarks
ruby benchmark/run_benchmarks.rb

# 3. Compare with seven_zip_ruby gem (password-protected archives)
ruby benchmark/compare_password_extraction.rb

# 4. Check for memory leaks
ruby benchmark/check_memory_leaks.rb

# 5. Detailed memory profiling (requires memory_profiler gem)
ruby benchmark/profile_memory.rb

# 6. C-level leak detection (requires Valgrind)
./benchmark/check_c_leaks.sh
```

## Test Archive Sizes

The generator creates archives of various sizes:

| Size    | Files | Size/File | Total Size | Use Case |
|---------|-------|-----------|------------|----------|
| Tiny    | 10    | 1 KB      | ~10 KB     | Quick tests |
| Small   | 50    | 10 KB     | ~500 KB    | Unit tests |
| Medium  | 100   | 100 KB    | ~10 MB     | Integration tests |
| Large   | 500   | 100 KB    | ~50 MB     | Performance tests |
| XLarge  | 1000  | 100 KB    | ~100 MB    | Stress tests |

Both encrypted and unencrypted versions are created for each size.

## Benchmark Operations

The performance benchmarks compare these operations:

1. **List entries** - Open archive and enumerate files
2. **Verify archive** - Integrity check with CRC validation
3. **Extract to files** - Extract all files to disk
4. **Extract to memory** - Extract files to RAM (StringIO)
5. **Open from memory** - Load archive from byte buffer

Each operation is benchmarked against the 7z CLI for comparison.

## Memory Leak Detection

### Ruby-Level Detection

`check_memory_leaks.rb` runs operations repeatedly and monitors:
- Process memory (RSS)
- Object allocations
- Memory growth trends

**Interpretation:**
- ✓ **OK**: Memory growth < 100 KB/iteration
- ⚠ **Warning**: Memory growth > 100 KB/iteration (potential leak)

### Detailed Profiling

`profile_memory.rb` uses the `memory_profiler` gem to track:
- Total allocated memory
- Retained objects (not garbage collected)
- Allocation locations (file and line)

**What to look for:**
- **Allocated memory**: Normal, gets garbage collected
- **Retained memory**: Potential leaks if > 0

### C-Level Detection

`check_c_leaks.sh` uses Valgrind to detect:
- Memory leaks in native code (7-Zip SDK)
- Invalid memory access
- Uninitialized values

**Focus on:**
- **Definitely lost**: Real leaks (should be 0)
- **Indirectly lost**: Leaked through pointers (should be 0)
- **Still reachable**: Normal for Ruby VM (ignore)

## Understanding Results

### Performance Benchmarks

Results show timing comparisons:

```
Operation              Ruby        7z CLI      Speedup
-------------------------------------------------------
List entries          5.2 ms      8.1 ms      1.56x faster
Extract to files      142 ms      138 ms      0.97x slower
```

**Speedup interpretation:**
- `> 1.0x`: Our library is faster
- `< 1.0x`: 7z CLI is faster
- Close to `1.0x`: Similar performance

**Expected results:**
- List entries: Similar or faster (native code)
- Extract to files: Similar (both use native extraction)
- Extract to memory: May be slower (extra copying)
- Open from memory: Faster (no file I/O)

### Comparison with seven_zip_ruby

The `compare_password_extraction.rb` benchmark compares three implementations:

**Benchmark results (password-protected archives):**
```
Archive: small_encrypted.7z (50 files)
  ruby_lzma:            180 ms
  seven_zip_ruby:       582 ms  (3.2x slower)
  7z CLI:               89 ms   (2.0x faster)

Archive: medium_encrypted.7z (100 files)
  ruby_lzma:            6.6 s
  seven_zip_ruby:       19.1 s  (2.9x slower)
  7z CLI:               216 ms  (30x faster)
```

**Key findings:**
- **~3x faster than seven_zip_ruby** for password-protected archives
- Achieved through archive caching optimization
- Archive opened once and reused for all extractions
- 7z CLI uses batch extraction and multiple threads vs our individual file extraction

**Why the difference:**
- `ruby_lzma`: Opens archive once, caches it, extracts files one-by-one
- `seven_zip_ruby`: Reopens archive for every file (no caching)
- `7z CLI`: Batch extracts all files in a single pass (optimal)

### Memory Leak Results

**Good result:**
```
✓ No memory leaks detected!
Memory growth: 50 KB/iteration (under threshold)
Object growth: 5 objects/iteration
```

**Bad result:**
```
⚠ POTENTIAL LEAK
Memory growth: 250 KB/iteration (above threshold)
Object growth: 150 objects/iteration
Trend: growing
```

If leaks are detected:
1. Run `profile_memory.rb` to see what's being retained
2. Run `check_c_leaks.sh` to check for C-level leaks
3. Review the code for missing `close()` calls or retained references

## Benchmark Files

### Generated Files

After running tests, you'll find:

```
benchmark/
├── fixtures/
│   ├── tiny.7z                  # Generated test archives
│   ├── tiny_encrypted.7z
│   ├── small.7z
│   └── ...
├── output/                      # Temporary extraction output (auto-deleted)
├── results.txt                  # Performance results
└── valgrind_report.txt          # C-level leak report (if run)
```

### Cleaning Up

Remove all generated files:

```bash
rm -rf benchmark/fixtures benchmark/output benchmark/results.txt benchmark/valgrind_report.txt
```

## Continuous Integration

Add to your CI pipeline:

```yaml
# .github/workflows/benchmark.yml
- name: Run benchmarks
  run: |
    brew install p7zip
    ruby benchmark/generate_test_archives.rb
    ruby benchmark/run_benchmarks.rb
    ruby benchmark/check_memory_leaks.rb
```

## Performance Tips

When benchmarking:
1. **Close other applications** to reduce noise
2. **Run multiple times** for statistical significance
3. **Warm up the cache** (results exclude first run)
4. **Check CPU throttling** (can affect results)

## Troubleshooting

### "7z command not found"

Install 7-Zip CLI:
```bash
brew install p7zip
```

### "Test archive not found"

Generate test archives first:
```bash
ruby benchmark/generate_test_archives.rb
```

### "memory_profiler gem not found"

Install the gem:
```bash
gem install memory_profiler
```

### Valgrind on macOS

The `check_c_leaks.sh` script automatically uses Docker on macOS since Valgrind doesn't work natively on Mac. Requirements:
- Docker Desktop must be installed and running
- First run will build a Docker image (takes ~1 minute)

If Docker is not available, alternatives include:
- Use Linux in CI/CD for Valgrind testing
- Use Instruments on macOS (`instruments -t Leaks`)

## Interpreting Memory Behavior

### Normal Memory Growth

Ruby's garbage collector doesn't always immediately free memory. Some growth is expected:
- **Minor growth**: GC will reclaim it later
- **Stable after warm-up**: Good
- **Continuous linear growth**: Potential leak

### Common False Positives

1. **String interning**: Ruby caches strings
2. **Method caching**: Ruby caches compiled methods
3. **Object pooling**: Some gems use object pools

### Real Leaks

Indicators of real leaks:
- Memory grows proportionally with iterations
- Memory never levels off
- C-level "definitely lost" bytes in Valgrind

## Contributing Benchmarks

To add new benchmarks:

1. Add test to `run_benchmarks.rb`
2. Add corresponding leak test to `check_memory_leaks.rb`
3. Update this README with expected results
4. Run full suite to verify

## References

- [7-Zip CLI Documentation](https://www.7-zip.org/7z.html)
- [Ruby memory_profiler](https://github.com/SamSaffron/memory_profiler)
- [Valgrind Documentation](https://valgrind.org/docs/manual/quick-start.html)
- [Ruby GC](https://docs.ruby-lang.org/en/master/GC.html)
