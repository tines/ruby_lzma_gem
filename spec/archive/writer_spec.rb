# frozen_string_literal: true

RSpec.describe RubyLzma::Archive::Writer do
  let(:output_dir) { File.join(__dir__, "..", "tmp") }
  let(:test_archive) { File.join(output_dir, "test_write.7z") }
  let(:test_file) { File.join(output_dir, "test_input.txt") }
  let(:test_file2) { File.join(output_dir, "test_input2.txt") }
  let(:test_data) { "Hello, World! This is test data." }
  let(:test_data2) { "Another file with different content." }

  before do
    FileUtils.mkdir_p(output_dir)
    File.write(test_file, test_data)
    File.write(test_file2, test_data2)
    FileUtils.rm_f(test_archive)
  end

  after do
    FileUtils.rm_f(test_archive)
    FileUtils.rm_f(test_file)
    FileUtils.rm_f(test_file2)
  end

  describe ".new" do
    it "creates a new archive writer" do
      writer = described_class.new(test_archive)
      expect(writer).to be_a(described_class)
      expect(writer.path).to eq(File.expand_path(test_archive))
      expect(writer.closed?).to be false
      writer.close
    end

    it "creates parent directories if needed" do
      nested_path = File.join(output_dir, "nested", "dir", "archive.7z")
      writer = described_class.new(nested_path)
      writer.close

      expect(File.exist?(nested_path)).to be true
      FileUtils.rm_rf(File.join(output_dir, "nested"))
    end
  end

  describe ".open" do
    it "automatically closes when used with a block" do
      writer = nil
      described_class.open(test_archive) do |w|
        writer = w
        expect(w.closed?).to be false
      end
      expect(writer.closed?).to be true
    end

    it "returns the writer when no block given" do
      writer = described_class.open(test_archive)
      expect(writer).to be_a(described_class)
      expect(writer.closed?).to be false
      writer.close
    end
  end

  describe "#add_file" do
    it "adds a file to the archive" do
      described_class.open(test_archive) do |writer|
        writer.add_file(test_file, "test.txt")
        expect(writer.size).to eq(1)
      end

      # Verify by reading back
      RubyLzma::Archive::Reader.open(test_archive) do |reader|
        expect(reader.size).to eq(1)
        expect(reader.entries.first.name).to eq("test.txt")
        expect(reader.extract_data(0)).to eq(test_data)
      end
    end

    it "uses filename as default archive path" do
      described_class.open(test_archive) do |writer|
        writer.add_file(test_file)
        expect(writer.size).to eq(1)
      end

      RubyLzma::Archive::Reader.open(test_archive) do |reader|
        expect(reader.entries.first.name).to eq(File.basename(test_file))
      end
    end

    it "raises error for non-existent file" do
      described_class.open(test_archive) do |writer|
        expect {
          writer.add_file("nonexistent.txt", "test.txt")
        }.to raise_error(RubyLzma::Error, /not found/i)
      end
    end

    it "adds multiple files" do
      described_class.open(test_archive) do |writer|
        writer.add_file(test_file, "file1.txt")
        writer.add_file(test_file2, "file2.txt")
        expect(writer.size).to eq(2)
      end

      RubyLzma::Archive::Reader.open(test_archive) do |reader|
        expect(reader.size).to eq(2)
        names = reader.entries.map(&:name).sort
        expect(names).to eq(["file1.txt", "file2.txt"])
      end
    end
  end

  describe "#add_data" do
    it "adds data from memory to the archive" do
      data = "This is in-memory data!"

      described_class.open(test_archive) do |writer|
        writer.add_data(data, "memory.txt")
        expect(writer.size).to eq(1)
      end

      RubyLzma::Archive::Reader.open(test_archive) do |reader|
        expect(reader.size).to eq(1)
        expect(reader.entries.first.name).to eq("memory.txt")
        expect(reader.extract_data(0)).to eq(data)
      end
    end

    it "handles binary data" do
      binary_data = "\x00\x01\x02\xFF\xFE\xFD".b

      described_class.open(test_archive) do |writer|
        writer.add_data(binary_data, "binary.bin")
      end

      RubyLzma::Archive::Reader.open(test_archive) do |reader|
        extracted = reader.extract_data(0)
        expect(extracted.bytes).to eq(binary_data.bytes)
      end
    end

    it "requires archive path" do
      described_class.open(test_archive) do |writer|
        expect {
          writer.add_data("test", "")
        }.to raise_error(RubyLzma::Error, /path is required/i)
      end
    end

    it "handles large data" do
      large_data = "x" * (1024 * 1024)  # 1 MB

      described_class.open(test_archive) do |writer|
        writer.add_data(large_data, "large.txt")
      end

      RubyLzma::Archive::Reader.open(test_archive) do |reader|
        expect(reader.extract_data(0)).to eq(large_data)
      end
    end
  end

  describe "#mkdir" do
    it "creates an empty directory in the archive" do
      described_class.open(test_archive) do |writer|
        writer.mkdir("empty_dir")
        expect(writer.size).to eq(1)
      end

      RubyLzma::Archive::Reader.open(test_archive) do |reader|
        expect(reader.size).to eq(1)
        entry = reader.entries.first
        expect(entry.name).to eq("empty_dir")
        expect(entry.directory?).to be true
      end
    end
  end

  describe "#size" do
    it "returns the number of entries added" do
      described_class.open(test_archive) do |writer|
        expect(writer.size).to eq(0)
        writer.add_file(test_file, "file1.txt")
        expect(writer.size).to eq(1)
        expect(writer.count).to eq(1)
        expect(writer.length).to eq(1)
        writer.add_data("test", "file2.txt")
        expect(writer.size).to eq(2)
      end
    end
  end

  describe "#close" do
    it "finalizes and writes the archive" do
      writer = described_class.new(test_archive)
      writer.add_file(test_file, "test.txt")
      expect(File.exist?(test_archive)).to be false

      writer.close
      expect(writer.closed?).to be true
      expect(File.exist?(test_archive)).to be true
      expect(File.size(test_archive)).to be > 0
    end

    it "is idempotent" do
      writer = described_class.new(test_archive)
      writer.add_file(test_file, "test.txt")
      writer.close

      expect { writer.close }.not_to raise_error
      expect(writer.closed?).to be true
    end
  end

  describe "with password" do
    let(:password) { "SecretPass123" }

    it "creates an encrypted archive" do
      described_class.open(test_archive, password: password) do |writer|
        writer.add_file(test_file, "secret.txt")
        writer.add_data("Secret message", "message.txt")
      end

      # Verify can read with correct password
      RubyLzma::Archive::Reader.open(test_archive, password: password) do |reader|
        expect(reader.size).to eq(2)
        expect(reader.extract_data(0)).to include("Secret")
      end
    end

    it "cannot be read without password" do
      described_class.open(test_archive, password: password) do |writer|
        writer.add_data("Secret data", "secret.txt")
      end

      # Should fail to extract without password
      RubyLzma::Archive::Reader.open(test_archive) do |reader|
        expect {
          reader.extract_data(0)
        }.to raise_error(RubyLzma::Error)
      end
    end

    it "fails with wrong password" do
      described_class.open(test_archive, password: password) do |writer|
        writer.add_data("Secret data", "secret.txt")
      end

      RubyLzma::Archive::Reader.open(test_archive, password: "WrongPassword") do |reader|
        expect {
          reader.extract_data(0)
        }.to raise_error(RubyLzma::Error)
      end
    end
  end

  describe "compression options" do
    it "creates archive with different compression levels" do
      # Store (no compression)
      store_archive = File.join(output_dir, "store.7z")
      described_class.open(store_archive, level: described_class::LEVEL_STORE) do |writer|
        writer.add_data("x" * 1000, "data.txt")
      end

      # Ultra compression
      ultra_archive = File.join(output_dir, "ultra.7z")
      described_class.open(ultra_archive, level: described_class::LEVEL_ULTRA) do |writer|
        writer.add_data("x" * 1000, "data.txt")
      end

      # Ultra should be smaller than store for repeated data
      store_size = File.size(store_archive)
      ultra_size = File.size(ultra_archive)

      expect(ultra_size).to be < store_size

      FileUtils.rm_f(store_archive)
      FileUtils.rm_f(ultra_archive)
    end
  end

  describe "#to_s and #inspect" do
    it "provides string representation" do
      described_class.open(test_archive) do |writer|
        writer.add_file(test_file, "test.txt")
        expect(writer.to_s).to include("Writer")
        expect(writer.to_s).to include("test_write.7z")
        expect(writer.to_s).to include("entries=1")
        expect(writer.to_s).to include("open")
      end
    end
  end

  describe "error handling" do
    it "raises error when adding file after close" do
      writer = described_class.new(test_archive)
      writer.close

      expect {
        writer.add_file(test_file, "test.txt")
      }.to raise_error(RubyLzma::Error, /closed/)
    end

    it "raises error when adding data after close" do
      writer = described_class.new(test_archive)
      writer.close

      expect {
        writer.add_data("test", "test.txt")
      }.to raise_error(RubyLzma::Error, /closed/)
    end
  end

  describe "Zip Slip protection (path traversal prevention)" do
    it "rejects paths with parent directory traversal (..)" do
      described_class.open(test_archive) do |writer|
        expect {
          writer.add_data("malicious", "../../../etc/passwd")
        }.to raise_error(RubyLzma::Archive::Writer::PathTraversalError, /directory traversal/)
      end
    end

    it "rejects paths with encoded parent traversal" do
      described_class.open(test_archive) do |writer|
        expect {
          writer.add_data("malicious", "foo/../../../bar")
        }.to raise_error(RubyLzma::Archive::Writer::PathTraversalError, /directory traversal/)
      end
    end

    it "rejects absolute Unix paths" do
      described_class.open(test_archive) do |writer|
        expect {
          writer.add_data("malicious", "/etc/passwd")
        }.to raise_error(RubyLzma::Archive::Writer::PathTraversalError, /absolute/)
      end
    end

    it "rejects absolute Windows paths" do
      described_class.open(test_archive) do |writer|
        expect {
          writer.add_data("malicious", "C:\\Windows\\System32\\config")
        }.to raise_error(RubyLzma::Archive::Writer::PathTraversalError, /absolute/)
      end
    end

    it "rejects paths with null bytes" do
      described_class.open(test_archive) do |writer|
        expect {
          writer.add_data("malicious", "foo\x00bar.txt")
        }.to raise_error(RubyLzma::Archive::Writer::PathTraversalError, /null bytes/)
      end
    end

    it "normalizes backslashes to forward slashes" do
      described_class.open(test_archive) do |writer|
        writer.add_data("test", "path\\to\\file.txt")
        expect(writer.size).to eq(1)
      end

      RubyLzma::Archive::Reader.open(test_archive) do |reader|
        # Path should be normalized
        expect(reader.entries.first.name).to eq("path/to/file.txt")
      end
    end

    it "removes leading ./ from paths" do
      described_class.open(test_archive) do |writer|
        writer.add_data("test", "./relative/path.txt")
        expect(writer.size).to eq(1)
      end

      RubyLzma::Archive::Reader.open(test_archive) do |reader|
        expect(reader.entries.first.name).to eq("relative/path.txt")
      end
    end

    it "collapses multiple consecutive slashes" do
      described_class.open(test_archive) do |writer|
        writer.add_data("test", "path//to///file.txt")
        expect(writer.size).to eq(1)
      end

      RubyLzma::Archive::Reader.open(test_archive) do |reader|
        expect(reader.entries.first.name).to eq("path/to/file.txt")
      end
    end

    it "applies path sanitization to add_file" do
      described_class.open(test_archive) do |writer|
        expect {
          writer.add_file(test_file, "../escape.txt")
        }.to raise_error(RubyLzma::Archive::Writer::PathTraversalError)
      end
    end

    it "applies path sanitization to mkdir" do
      described_class.open(test_archive) do |writer|
        expect {
          writer.mkdir("../../../escape_dir")
        }.to raise_error(RubyLzma::Archive::Writer::PathTraversalError)
      end
    end

    it "allows legitimate nested paths" do
      described_class.open(test_archive) do |writer|
        writer.add_data("test", "deeply/nested/path/to/file.txt")
        writer.mkdir("another/nested/directory")
        expect(writer.size).to eq(2)
      end

      RubyLzma::Archive::Reader.open(test_archive) do |reader|
        expect(reader.size).to eq(2)
      end
    end
  end
end

