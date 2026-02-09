# frozen_string_literal: true

RSpec.describe RubyLzma::Format do
  describe ".detect" do
    it "detects 7z format from extension" do
      format = described_class.detect("archive.7z")
      expect(format).to eq(RubyLzma::FFI::Constants::SZ_FORMAT_7Z)
    end

    it "detects ZIP format from extension" do
      format = described_class.detect("archive.zip")
      expect(format).to eq(RubyLzma::FFI::Constants::SZ_FORMAT_ZIP)
    end

    it "detects TAR format from extension" do
      format = described_class.detect("archive.tar")
      expect(format).to eq(RubyLzma::FFI::Constants::SZ_FORMAT_TAR)
    end

    it "defaults to 7z for unknown extensions" do
      format = described_class.detect("archive.unknown")
      expect(format).to eq(RubyLzma::FFI::Constants::SZ_FORMAT_7Z)
    end

    it "is case insensitive" do
      format = described_class.detect("ARCHIVE.7Z")
      expect(format).to eq(RubyLzma::FFI::Constants::SZ_FORMAT_7Z)
    end
  end

  describe ".supported?" do
    it "returns true for 7z format" do
      expect(described_class.supported?(RubyLzma::FFI::Constants::SZ_FORMAT_7Z)).to be true
    end

    it "returns true for ZIP format" do
      expect(described_class.supported?(RubyLzma::FFI::Constants::SZ_FORMAT_ZIP)).to be true
    end

    it "returns true for TAR format" do
      expect(described_class.supported?(RubyLzma::FFI::Constants::SZ_FORMAT_TAR)).to be true
    end
  end

  describe ".name" do
    it "returns format name for 7z" do
      expect(described_class.name(RubyLzma::FFI::Constants::SZ_FORMAT_7Z)).to eq("7z")
    end

    it "returns format name for ZIP" do
      expect(described_class.name(RubyLzma::FFI::Constants::SZ_FORMAT_ZIP)).to eq("zip")
    end

    it "returns format name for TAR" do
      expect(described_class.name(RubyLzma::FFI::Constants::SZ_FORMAT_TAR)).to eq("tar")
    end

    it "returns 'unknown' for unknown format" do
      expect(described_class.name(999)).to eq("unknown")
    end
  end

  describe ".seven_zip?" do
    it "returns true for 7z archives" do
      archive_path = fixture_path("test.7z")
      expect(described_class.seven_zip?(archive_path)).to be true
    end

    it "returns false for non-7z files" do
      # Create a temporary non-7z file
      temp_file = File.join(__dir__, "tmp", "not_7z.txt")
      FileUtils.mkdir_p(File.dirname(temp_file))
      File.write(temp_file, "This is not a 7z file")

      expect(described_class.seven_zip?(temp_file)).to be false

      FileUtils.rm(temp_file)
    end

    it "returns false for non-existent files" do
      expect(described_class.seven_zip?("nonexistent.7z")).to be false
    end

    it "returns false for files smaller than signature" do
      temp_file = File.join(__dir__, "tmp", "small.txt")
      FileUtils.mkdir_p(File.dirname(temp_file))
      File.write(temp_file, "Hi")

      expect(described_class.seven_zip?(temp_file)).to be false

      FileUtils.rm(temp_file)
    end
  end
end
