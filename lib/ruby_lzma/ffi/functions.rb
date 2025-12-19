# frozen_string_literal: true

require_relative "library"
require_relative "types"

module RubyLzma
  module FFI
    module Functions
      extend Library

      # Archive operations
      attach_function :sz_open_archive, [:string, :int, :pointer], :pointer
      attach_function :sz_close_archive, [:pointer], :int
      attach_function :sz_get_entry_count, [:pointer], :uint32
      attach_function :sz_get_entry_info, [:pointer, :uint32, Types::EntryInfo.by_ref], :int

      # Extraction operations
      attach_function :sz_extract_to_file, [:pointer, :uint32, :string], :int
      attach_function :sz_extract_to_memory, [:pointer, :uint32, :pointer, :pointer], :int
      attach_function :sz_verify, [:pointer], :int

      # Memory management
      attach_function :sz_free, [:pointer], :void

      # Configuration
      attach_function :sz_set_password, [:pointer, :string], :int
      attach_function :sz_set_progress_callback, [:pointer, :progress_callback, :pointer], :int

      # Helper method to check error codes and raise exceptions
      def self.check_error(error_code)
        return if error_code == Constants::SZW_OK

        message = Constants::ERROR_MESSAGES[error_code] || "Unknown error (code: #{error_code})"
        raise Error, message
      end

      # Helper method to allocate error code pointer
      def self.error_pointer
        ::FFI::MemoryPointer.new(:int)
      end
    end
  end
end
