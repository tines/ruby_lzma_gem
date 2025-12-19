# frozen_string_literal: true

RSpec.describe "Encrypted Archives" do
  let(:encrypted_archive) { fixture_path("test_encrypted.7z") }

  describe "opening encrypted archives" do
    it "can open and list entries in encrypted archives" do
      reader = RubyLzma::Archive::Reader.new(encrypted_archive)

      expect(reader.size).to eq(1)
      expect(reader.entries.first.name).to include("secret.txt")

      reader.close
    end

    it "fails to extract files from encrypted archives without password" do
      reader = RubyLzma::Archive::Reader.new(encrypted_archive)

      # Extraction should fail without password
      expect {
        reader.extract(0, File.join(__dir__, "../tmp/extracted.txt"))
      }.to raise_error(RubyLzma::Error, /extraction failed/i)

      reader.close
    end

    it "successfully extracts files from encrypted archives with correct password" do
      reader = RubyLzma::Archive::Reader.new(encrypted_archive, password: "TestPass123")

      output_path = File.join(__dir__, "../tmp/extracted_secret.txt")
      FileUtils.mkdir_p(File.dirname(output_path))

      # Should successfully extract with correct password
      expect {
        reader.extract(0, output_path)
      }.not_to raise_error

      # Verify file was extracted
      expect(File.exist?(output_path)).to be true
      expect(File.read(output_path)).to include("Secret")

      FileUtils.rm_f(output_path)
      reader.close
    end

    it "fails to extract with wrong password" do
      reader = RubyLzma::Archive::Reader.new(encrypted_archive, password: "WrongPassword")

      expect {
        reader.extract(0, File.join(__dir__, "../tmp/extracted.txt"))
      }.to raise_error(RubyLzma::Error, /extraction failed/i)

      reader.close
    end
  end

  describe "metadata access" do
    it "can read entry metadata from encrypted archives" do
      RubyLzma::Archive::Reader.open(encrypted_archive) do |reader|
        entry = reader.entries.first

        expect(entry.file?).to be true
        expect(entry.name).to include("secret.txt")
        expect(entry.size).to be > 0
      end
    end
  end
end
