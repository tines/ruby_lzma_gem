# frozen_string_literal: true

module RubyLzma
  # Format detection and helpers
  module Format
    # Detect archive format from file extension
    #
    # @param path [String] Path to archive file
    # @return [Integer] Format constant
    def self.detect(path)
      ext = File.extname(path).downcase
      case ext
      when ".7z"
        FFI::Constants::SZ_FORMAT_7Z
      when ".zip"
        # Note: ZIP format requires C++ API
        FFI::Constants::SZ_FORMAT_ZIP
      when ".tar"
        # Note: TAR format requires C++ API
        FFI::Constants::SZ_FORMAT_TAR
      else
        # Default to 7z format
        FFI::Constants::SZ_FORMAT_7Z
      end
    end

    # Check if format is supported
    #
    # @param format [Integer] Format constant
    # @return [Boolean] true if fully supported
    def self.supported?(format)
      [FFI::Constants::SZ_FORMAT_7Z,
       FFI::Constants::SZ_FORMAT_ZIP,
       FFI::Constants::SZ_FORMAT_TAR].include?(format)
    end

    # Get format name
    #
    # @param format [Integer] Format constant
    # @return [String] Format name
    def self.name(format)
      FFI::Constants::FORMAT_NAMES[format] || "unknown"
    end

    # Check if file appears to be a 7z archive by signature
    #
    # @param path [String] Path to file
    # @return [Boolean] true if file has 7z signature
    def self.seven_zip?(path)
      return false unless File.exist?(path)
      return false if File.size(path) < 6

      File.open(path, "rb") do |f|
        signature = f.read(6)
        # 7z signature: '7' 'z' 0xBC 0xAF 0x27 0x1C
        signature == "7z\xBC\xAF\x27\x1C".b
      end
    rescue
      false
    end
  end
end
