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
end
