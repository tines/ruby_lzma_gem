# frozen_string_literal: true

RSpec.describe "Multi-format Archive Support" do
  let(:test_7z) { fixture_path("test.7z") }
  let(:test_zip) { fixture_path("test.zip") }
  let(:test_tar) { fixture_path("test.tar") }
  let(:encrypted_zip) { fixture_path("test_encrypted.zip") }
  let(:output_dir) { File.join(__dir__, "..", "tmp", "multi_format") }

  before do
    FileUtils.mkdir_p(output_dir)
  end

  after do
    FileUtils.rm_rf(output_dir)
  end

  describe "ZIP format" do
    it "opens and reads a ZIP archive" do
      RubyLzma::Archive::Reader.open(test_zip, format: RubyLzma::FFI::Constants::SZ_FORMAT_ZIP) do |reader|
        expect(reader.size).to eq(2)

        names = reader.entries.map(&:name)
        expect(names).to include("test.txt")
        expect(names).to include("test2.txt")
      end
    end

    it "extracts files from a ZIP archive" do
      RubyLzma::Archive::Reader.open(test_zip, format: RubyLzma::FFI::Constants::SZ_FORMAT_ZIP) do |reader|
        entry = reader.entries.find { |e| e.name == "test.txt" }
        expect(entry).not_to be_nil

        data = reader.extract_data(entry)
        expect(data).to eq("Hello, World!")
      end
    end

    it "extracts all files from a ZIP archive" do
      RubyLzma::Archive::Reader.open(test_zip, format: RubyLzma::FFI::Constants::SZ_FORMAT_ZIP) do |reader|
        reader.extract_all(output_dir)

        files = Dir.glob("#{output_dir}/**/*").select { |f| File.file?(f) }
        expect(files.size).to eq(2)
      end
    end

    it "opens a ZIP archive from memory buffer" do
      data = File.binread(test_zip)
      RubyLzma::Archive::Reader.open_buffer(data, format: RubyLzma::FFI::Constants::SZ_FORMAT_ZIP) do |reader|
        expect(reader.size).to eq(2)
        extracted = reader.extract_data(0)
        expect(extracted).not_to be_empty
      end
    end

    it "opens a ZIP archive from StringIO" do
      require "stringio"
      data = File.binread(test_zip)
      buffer = StringIO.new(data)

      RubyLzma::Archive::Reader.open_buffer(buffer, format: RubyLzma::FFI::Constants::SZ_FORMAT_ZIP) do |reader|
        expect(reader.size).to eq(2)
      end
    end

    it "opens encrypted ZIP with correct password" do
      RubyLzma::Archive::Reader.open(
        encrypted_zip,
        format: RubyLzma::FFI::Constants::SZ_FORMAT_ZIP,
        password: "TestPass123"
      ) do |reader|
        expect(reader.size).to eq(1)
        expect(reader.entries.first.name).to eq("secret.txt")

        data = reader.extract_data(0)
        expect(data).to eq("Secret ZIP content")
      end
    end
  end

  describe "TAR format" do
    it "opens and reads a TAR archive" do
      RubyLzma::Archive::Reader.open(test_tar, format: RubyLzma::FFI::Constants::SZ_FORMAT_TAR) do |reader|
        # TAR may include additional entries (e.g., directory entries, metadata)
        expect(reader.size).to be >= 2

        names = reader.entries.map(&:name)
        expect(names).to include("test.txt")
        expect(names).to include("test2.txt")
      end
    end

    it "extracts files from a TAR archive" do
      RubyLzma::Archive::Reader.open(test_tar, format: RubyLzma::FFI::Constants::SZ_FORMAT_TAR) do |reader|
        entry = reader.entries.find { |e| e.name == "test.txt" }
        expect(entry).not_to be_nil

        data = reader.extract_data(entry)
        expect(data).to eq("Hello, World!")
      end
    end

    it "extracts all files from a TAR archive" do
      RubyLzma::Archive::Reader.open(test_tar, format: RubyLzma::FFI::Constants::SZ_FORMAT_TAR) do |reader|
        reader.extract_all(output_dir)

        files = Dir.glob("#{output_dir}/**/*").select { |f| File.file?(f) }
        expect(files.size).to eq(2)
      end
    end

    it "opens a TAR archive from memory buffer" do
      data = File.binread(test_tar)
      RubyLzma::Archive::Reader.open_buffer(data, format: RubyLzma::FFI::Constants::SZ_FORMAT_TAR) do |reader|
        expect(reader.size).to be >= 2

        file_entry = reader.entries.find { |e| e.file? }
        expect(file_entry).not_to be_nil
        extracted = reader.extract_data(file_entry)
        expect(extracted).not_to be_empty
      end
    end
  end

  describe "7z format (regression)" do
    it "continues to work with default format" do
      RubyLzma::Archive::Reader.open(test_7z) do |reader|
        expect(reader.size).to eq(3)
      end
    end

    it "continues to work with explicit 7z format" do
      RubyLzma::Archive::Reader.open(test_7z, format: RubyLzma::FFI::Constants::SZ_FORMAT_7Z) do |reader|
        expect(reader.size).to eq(3)
      end
    end
  end

  describe "StringIO handling" do
    it "handles StringIO without requiring it externally" do
      # This tests the fix for the StringIO NameError bug
      # The reader.rb now requires 'stringio' itself
      data = File.binread(test_7z)
      buffer = StringIO.new(data)

      RubyLzma::Archive::Reader.open_buffer(buffer) do |reader|
        expect(reader.size).to eq(3)
      end
    end

    it "handles plain String buffers" do
      data = File.binread(test_7z)

      RubyLzma::Archive::Reader.open_buffer(data) do |reader|
        expect(reader.size).to eq(3)
      end
    end

    it "handles StringIO with ZIP format" do
      data = File.binread(test_zip)
      buffer = StringIO.new(data)

      RubyLzma::Archive::Reader.open_buffer(buffer, format: RubyLzma::FFI::Constants::SZ_FORMAT_ZIP) do |reader|
        expect(reader.size).to eq(2)
      end
    end
  end

  describe "format error handling" do
    it "raises error when opening a ZIP with 7z format" do
      expect {
        RubyLzma::Archive::Reader.new(test_zip, format: RubyLzma::FFI::Constants::SZ_FORMAT_7Z)
      }.to raise_error(RubyLzma::Error)
    end

    it "raises error when opening a TAR with 7z format" do
      expect {
        RubyLzma::Archive::Reader.new(test_tar, format: RubyLzma::FFI::Constants::SZ_FORMAT_7Z)
      }.to raise_error(RubyLzma::Error)
    end
  end
end
