# frozen_string_literal: true

module RubyLzma
  module FFI
    module Constants
      # Error codes matching C definitions from lzma_sdk_wrapper.h
      SZW_OK = 0
      SZW_ERROR_FAIL = 1
      SZW_ERROR_OUTOFMEMORY = 2
      SZW_ERROR_INVALIDARG = 3
      SZW_ERROR_OPEN_FAILED = 4
      SZW_ERROR_READ_FAILED = 5
      SZW_ERROR_WRITE_FAILED = 6
      SZW_ERROR_EXTRACT_FAILED = 7
      SZW_ERROR_COMPRESS_FAILED = 8
      SZW_ERROR_PASSWORD_REQUIRED = 9
      SZW_ERROR_PASSWORD_INCORRECT = 10
      SZW_ERROR_CORRUPT_ARCHIVE = 11
      SZW_ERROR_UNSUPPORTED_FORMAT = 12

      # Archive formats
      SZ_FORMAT_7Z = 0
      SZ_FORMAT_ZIP = 1
      SZ_FORMAT_TAR = 2

      # Compression methods
      SZ_METHOD_LZMA = 0
      SZ_METHOD_LZMA2 = 1
      SZ_METHOD_PPMD = 2
      SZ_METHOD_BZIP2 = 3
      SZ_METHOD_DEFLATE = 4

      # Compression levels
      SZ_LEVEL_STORE = 0
      SZ_LEVEL_FASTEST = 1
      SZ_LEVEL_FAST = 3
      SZ_LEVEL_NORMAL = 5
      SZ_LEVEL_MAXIMUM = 7
      SZ_LEVEL_ULTRA = 9

      # Error code to exception mapping
      ERROR_MESSAGES = {
        SZW_ERROR_FAIL => "Operation failed",
        SZW_ERROR_OUTOFMEMORY => "Out of memory",
        SZW_ERROR_INVALIDARG => "Invalid argument",
        SZW_ERROR_OPEN_FAILED => "Failed to open archive",
        SZW_ERROR_READ_FAILED => "Read operation failed",
        SZW_ERROR_WRITE_FAILED => "Write operation failed",
        SZW_ERROR_EXTRACT_FAILED => "Extraction failed",
        SZW_ERROR_COMPRESS_FAILED => "Compression failed",
        SZW_ERROR_PASSWORD_REQUIRED => "Password required",
        SZW_ERROR_PASSWORD_INCORRECT => "Incorrect password",
        SZW_ERROR_CORRUPT_ARCHIVE => "Archive is corrupt",
        SZW_ERROR_UNSUPPORTED_FORMAT => "Unsupported archive format"
      }.freeze

      # Format names for display
      FORMAT_NAMES = {
        SZ_FORMAT_7Z => "7z",
        SZ_FORMAT_ZIP => "zip",
        SZ_FORMAT_TAR => "tar"
      }.freeze
    end
  end
end
