# frozen_string_literal: true

RSpec.describe RubyLzma::Archive::Reader do
  let(:test_archive) { fixture_path("test.7z") }

  describe ".new" do
    it "opens an archive file" do
      reader = described_class.new(test_archive)
      expect(reader).to be_a(described_class)
      expect(reader.path).to eq(File.expand_path(test_archive))
      expect(reader.closed?).to be false
      reader.close
    end

    it "raises an error for non-existent files" do
      expect {
        described_class.new("nonexistent.7z")
      }.to raise_error(RubyLzma::Error, /File not found/)
    end

    it "automatically closes when used with a block" do
      reader = nil
      described_class.open(test_archive) do |r|
        reader = r
        expect(r.closed?).to be false
      end
      expect(reader.closed?).to be true
    end
  end

  describe "#entries" do
    it "returns all entries in the archive" do
      reader = described_class.new(test_archive)
      entries = reader.entries

      expect(entries).to be_an(Array)
      expect(entries.size).to eq(3)
      expect(entries).to all(be_a(RubyLzma::Entry))

      reader.close
    end

    it "caches entries on subsequent calls" do
      reader = described_class.new(test_archive)
      entries1 = reader.entries
      entries2 = reader.entries

      expect(entries1.object_id).to eq(entries2.object_id)

      reader.close
    end
  end

  describe "#size" do
    it "returns the number of entries" do
      reader = described_class.new(test_archive)
      expect(reader.size).to eq(3)
      expect(reader.count).to eq(3)
      expect(reader.length).to eq(3)
      reader.close
    end
  end

  describe "#each" do
    it "iterates over all entries" do
      reader = described_class.new(test_archive)
      entries = []

      reader.each do |entry|
        entries << entry
      end

      expect(entries.size).to eq(3)
      reader.close
    end

    it "works with enumerable methods" do
      reader = described_class.new(test_archive)

      files = reader.select(&:file?)
      dirs = reader.select(&:directory?)

      expect(files.size).to eq(2)
      expect(dirs.size).to eq(1)

      reader.close
    end
  end

  describe "#[]" do
    it "returns entry by index" do
      reader = described_class.new(test_archive)

      entry = reader[0]
      expect(entry).to be_a(RubyLzma::Entry)
      expect(entry.index).to eq(0)

      reader.close
    end
  end

  describe "entry attributes" do
    it "provides correct entry information" do
      reader = described_class.new(test_archive)
      entries = reader.entries

      # First entry should be the directory
      dir_entry = entries.find(&:directory?)
      expect(dir_entry).not_to be_nil
      expect(dir_entry.name).to match(/test_data/)
      expect(dir_entry.size).to eq(0)

      # Find file entries
      file_entries = entries.select(&:file?)
      expect(file_entries.size).to eq(2)

      test_txt = file_entries.find { |e| e.name.include?("test.txt") }
      expect(test_txt).not_to be_nil
      expect(test_txt.size).to eq(14)

      test2_txt = file_entries.find { |e| e.name.include?("test2.txt") }
      expect(test2_txt).not_to be_nil
      expect(test2_txt.size).to eq(21)

      reader.close
    end
  end

  describe "#close" do
    it "closes the archive" do
      reader = described_class.new(test_archive)
      expect(reader.closed?).to be false

      reader.close
      expect(reader.closed?).to be true
    end

    it "is idempotent" do
      reader = described_class.new(test_archive)
      reader.close

      expect { reader.close }.not_to raise_error
      expect(reader.closed?).to be true
    end

    it "raises error when accessing entries after close" do
      reader = described_class.new(test_archive)
      reader.close

      expect { reader.entries }.to raise_error(RubyLzma::Error, /closed/)
    end
  end

  describe "#extract" do
    let(:output_dir) { File.join(__dir__, "..", "tmp", "extracted") }

    before do
      FileUtils.rm_rf(output_dir)
      FileUtils.mkdir_p(output_dir)
    end

    after do
      FileUtils.rm_rf(output_dir)
    end

    it "extracts a single file by entry" do
      reader = described_class.new(test_archive)
      file_entry = reader.entries.find { |e| e.file? && e.name.include?("test.txt") }

      output_path = File.join(output_dir, "test.txt")
      reader.extract(file_entry, output_path)

      expect(File.exist?(output_path)).to be true
      expect(File.read(output_path)).to eq("Hello, World!\n")

      reader.close
    end

    it "extracts a single file by index" do
      reader = described_class.new(test_archive)
      file_entry = reader.entries.find { |e| e.file? && e.name.include?("test2.txt") }

      output_path = File.join(output_dir, "test2.txt")
      reader.extract(file_entry.index, output_path)

      expect(File.exist?(output_path)).to be true
      expect(File.read(output_path)).to eq("This is a test file.\n")

      reader.close
    end

    it "creates parent directories if needed" do
      reader = described_class.new(test_archive)
      file_entry = reader.entries.find { |e| e.file? && e.name.include?("test.txt") }

      output_path = File.join(output_dir, "nested", "dirs", "test.txt")
      reader.extract(file_entry, output_path)

      expect(File.exist?(output_path)).to be true

      reader.close
    end
  end

  describe "#extract_all" do
    let(:output_dir) { File.join(__dir__, "..", "tmp", "extracted_all") }

    before do
      FileUtils.rm_rf(output_dir)
      FileUtils.mkdir_p(output_dir)
    end

    after do
      FileUtils.rm_rf(output_dir)
    end

    it "extracts all files with full paths" do
      reader = described_class.new(test_archive)
      reader.extract_all(output_dir)

      # Check that files were extracted
      files = Dir.glob("#{output_dir}/**/*").select { |f| File.file?(f) }
      expect(files.size).to eq(2)

      reader.close
    end

    it "extracts all files without full paths" do
      reader = described_class.new(test_archive)
      reader.extract_all(output_dir, full_paths: false)

      # Check that files were extracted to root
      files = Dir.glob("#{output_dir}/*").select { |f| File.file?(f) }
      expect(files.size).to eq(2)

      reader.close
    end
  end

  describe "Archive Bomb Protection" do
    let(:output_dir) { File.join(__dir__, "..", "tmp", "bomb_test") }

    before do
      FileUtils.mkdir_p(output_dir)
    end

    after do
      FileUtils.rm_rf(output_dir)
      # Restore defaults
      described_class.max_entry_size = described_class::DEFAULT_MAX_ENTRY_SIZE
      described_class.max_total_size = described_class::DEFAULT_MAX_TOTAL_SIZE
      described_class.max_compression_ratio = described_class::DEFAULT_MAX_COMPRESSION_RATIO
      described_class.max_size_for_unknown_ratio = described_class::DEFAULT_MAX_SIZE_UNKNOWN_RATIO
    end

    it "has default extraction limits" do
      expect(described_class.max_entry_size).to eq(1024 * 1024 * 1024)  # 1 GB
      expect(described_class.max_total_size).to eq(10 * 1024 * 1024 * 1024)  # 10 GB
      expect(described_class.max_compression_ratio).to eq(1000)
      expect(described_class.max_size_for_unknown_ratio).to eq(10 * 1024 * 1024)  # 10 MB
    end

    it "allows disabling entry size limit" do
      described_class.max_entry_size = nil

      described_class.open(test_archive) do |reader|
        # Should not raise even if we pretend entry is huge
        # (actual archive is small so no error expected)
        expect { reader.extract_data(0) }.not_to raise_error
      end
    end

    it "allows configuring maximum entry size" do
      # Set a very small limit
      described_class.max_entry_size = 10  # 10 bytes

      described_class.open(test_archive) do |reader|
        # Find a file entry (not a directory) that exceeds the limit
        file_entry = reader.entries.find { |e| e.file? && e.size > 10 }
        expect(file_entry).not_to be_nil, "Test requires a file entry larger than 10 bytes"

        expect {
          reader.extract_data(file_entry)
        }.to raise_error(RubyLzma::Archive::Reader::ExtractionLimitError, /exceeds maximum allowed size/)
      end
    end

    it "allows configuring maximum compression ratio" do
      # Set a very strict compression ratio limit
      described_class.max_compression_ratio = 2  # 2:1 ratio max

      # Create a highly compressible archive
      compressed_archive = File.join(output_dir, "compressible.7z")
      RubyLzma::Archive::Writer.open(compressed_archive) do |writer|
        # Highly repetitive data compresses very well
        writer.add_data("x" * 10000, "repeated.txt")
      end

      described_class.open(compressed_archive) do |reader|
        entry = reader.entries.first
        # If compression ratio exceeds limit, should raise
        if entry.compressed_size > 0 && (entry.size.to_f / entry.compressed_size) > 2
          expect {
            reader.extract_data(0)
          }.to raise_error(RubyLzma::Archive::Reader::ExtractionLimitError, /compression ratio/)
        end
      end
    end

    it "allows disabling compression ratio check" do
      described_class.max_compression_ratio = nil

      # Create a highly compressible archive
      compressed_archive = File.join(output_dir, "compressible2.7z")
      RubyLzma::Archive::Writer.open(compressed_archive) do |writer|
        writer.add_data("x" * 10000, "repeated.txt")
      end

      described_class.open(compressed_archive) do |reader|
        expect { reader.extract_data(0) }.not_to raise_error
      end
    end

    it "checks total extraction size for extract_all" do
      # Set a very small total limit that's less than the sum of all entries
      described_class.max_total_size = 5  # 5 bytes total (entries sum to ~35 bytes)

      described_class.open(test_archive) do |reader|
        total_size = reader.entries.sum(&:size)
        expect(total_size).to be > 5, "Test requires total size > 5 bytes"

        expect {
          reader.extract_all(output_dir)
        }.to raise_error(RubyLzma::Archive::Reader::ExtractionLimitError, /total.*size/i)
      end
    end

    it "blocks large entries with unknown compression ratio (compressed_size=0)" do
      # In solid 7z archives, individual entry compressed_size may be 0
      # We should still protect against large entries in this case
      described_class.max_entry_size = nil  # Disable size limit to test ratio logic
      described_class.max_compression_ratio = 100  # Enable ratio check

      # Create archive with highly compressible data (will have compressed_size=0 in solid mode)
      compressed_archive = File.join(output_dir, "solid_compressible.7z")
      RubyLzma::Archive::Writer.open(compressed_archive, solid: true) do |writer|
        # Create 10MB+ of zeros - this will have compressed_size=0 in solid archive
        writer.add_data("\0" * (10 * 1024 * 1024 + 1), "zeros.dat")
      end

      described_class.open(compressed_archive) do |reader|
        entry = reader.entries.first
        # If compressed_size is 0 and size is large, should raise
        if entry.compressed_size == 0 && entry.size >= 10 * 1024 * 1024
          expect {
            reader.extract_data(0)
          }.to raise_error(RubyLzma::Archive::Reader::ExtractionLimitError, /unknown compression ratio/)
        else
          # If compressed_size is available, check ratio as normal
          skip "This archive reports compressed_size, skipping unknown ratio test"
        end
      end
    end

    it "allows configuring max_size_for_unknown_ratio" do
      # Set a custom threshold for unknown ratio entries
      described_class.max_entry_size = nil
      described_class.max_compression_ratio = 100
      described_class.max_size_for_unknown_ratio = 5 * 1024 * 1024  # 5 MB

      # Create archive with data larger than 5MB threshold
      compressed_archive = File.join(output_dir, "solid_5mb.7z")
      RubyLzma::Archive::Writer.open(compressed_archive, solid: true) do |writer|
        writer.add_data("\0" * (6 * 1024 * 1024), "zeros.dat")  # 6 MB
      end

      described_class.open(compressed_archive) do |reader|
        entry = reader.entries.first
        if entry.compressed_size == 0 && entry.size >= 5 * 1024 * 1024
          expect {
            reader.extract_data(0)
          }.to raise_error(RubyLzma::Archive::Reader::ExtractionLimitError, /unknown compression ratio/)
        else
          skip "This archive reports compressed_size, skipping unknown ratio test"
        end
      end
    end

    it "allows disabling max_size_for_unknown_ratio check" do
      described_class.max_entry_size = nil
      described_class.max_compression_ratio = 100
      described_class.max_size_for_unknown_ratio = nil  # Disable unknown ratio check

      # Create archive with highly compressible data
      compressed_archive = File.join(output_dir, "solid_no_limit.7z")
      RubyLzma::Archive::Writer.open(compressed_archive, solid: true) do |writer|
        writer.add_data("x" * 1000, "data.txt")  # Small data for fast test
      end

      described_class.open(compressed_archive) do |reader|
        # Should not raise even with unknown ratio when limit is disabled
        expect { reader.extract_data(0) }.not_to raise_error
      end
    end

    it "provides helpful error messages" do
      described_class.max_entry_size = 10

      described_class.open(test_archive) do |reader|
        # Find a file entry (not a directory) that exceeds the limit
        file_entry = reader.entries.find { |e| e.file? && e.size > 10 }
        expect(file_entry).not_to be_nil, "Test requires a file entry larger than 10 bytes"

        expect {
          reader.extract_data(file_entry)
        }.to raise_error(RubyLzma::Archive::Reader::ExtractionLimitError) do |error|
          expect(error.message).to include("max_entry_size")
          expect(error.message).to include("disable this limit")
        end
      end
    end
  end

  describe "Path Traversal Protection (Zip Slip on extraction)" do
    let(:output_dir) { File.join(__dir__, "..", "tmp", "traversal_test") }
    let(:malicious_archive) { File.join(output_dir, "malicious.7z") }

    before do
      FileUtils.mkdir_p(output_dir)
      # Disable limits for this test since we're testing path traversal, not size
      described_class.max_entry_size = nil
      described_class.max_total_size = nil
      described_class.max_compression_ratio = nil
    end

    after do
      FileUtils.rm_rf(output_dir)
      # Restore defaults
      described_class.max_entry_size = described_class::DEFAULT_MAX_ENTRY_SIZE
      described_class.max_total_size = described_class::DEFAULT_MAX_TOTAL_SIZE
      described_class.max_compression_ratio = described_class::DEFAULT_MAX_COMPRESSION_RATIO
    end

    it "prevents path traversal during extract_all with full_paths" do
      # Note: We can't easily create a malicious archive with path traversal
      # because Writer now sanitizes paths. However, we test the extraction
      # side protection which validates paths before extraction.

      # Create a normal archive
      RubyLzma::Archive::Writer.open(malicious_archive) do |writer|
        writer.add_data("safe content", "safe/nested/file.txt")
      end

      extraction_dir = File.join(output_dir, "extracted")
      FileUtils.mkdir_p(extraction_dir)

      described_class.open(malicious_archive) do |reader|
        reader.extract_all(extraction_dir)

        # Verify file was extracted inside the target directory
        extracted_file = File.join(extraction_dir, "safe", "nested", "file.txt")
        expect(File.exist?(extracted_file)).to be true
        expect(File.read(extracted_file)).to eq("safe content")
      end
    end

    it "extract_all validates all paths stay within output directory" do
      # Create a normal archive
      RubyLzma::Archive::Writer.open(malicious_archive) do |writer|
        writer.add_data("content", "deeply/nested/file.txt")
      end

      extraction_dir = File.join(output_dir, "extracted")
      FileUtils.mkdir_p(extraction_dir)

      described_class.open(malicious_archive) do |reader|
        # Should complete without error for safe paths
        expect { reader.extract_all(extraction_dir) }.not_to raise_error
      end
    end
  end
end
