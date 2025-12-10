# frozen_string_literal: true

module RubyLzma
  # Base error class for all RubyLzma errors
  class Error < StandardError; end

  # Raised when an invalid argument is provided
  class InvalidArgumentError < Error; end

  # Raised when memory allocation fails
  class OutOfMemoryError < Error; end

  # Raised when an operation is not supported
  class NotSupportedError < Error; end

  # Raised when CRC check fails
  class CRCError < Error; end

  # Raised when there's an archive format error
  class ArchiveError < Error; end

  # Raised when archive is encrypted but no password provided
  class EncryptedError < Error; end

  # Raised when password is invalid
  class PasswordError < Error; end

  # Raised when I/O error occurs
  class IOError < Error; end
end
