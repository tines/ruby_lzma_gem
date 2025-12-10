# frozen_string_literal: true

module RubyLzma
  # Gem version (follows semantic versioning)
  VERSION = "0.1.0"

  # Get LZMA SDK version
  # @return [String] SDK version (e.g., "25.01")
  def self.sdk_version
    require_relative "ffi/library"
    FFI::Library.sz_get_version
  end

  # Get full SDK info with copyright
  # @return [String] SDK version with copyright and date
  def self.sdk_info
    require_relative "ffi/library"
    FFI::Library.sz_get_sdk_info
  end
end
