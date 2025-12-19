# frozen_string_literal: true

require "ffi"
require_relative "types"
require_relative "constants"

module RubyLzma
  module FFI
    module Library
      extend ::FFI::Library

      # Detect platform and find the compiled library
      def self.library_path
        base_path = File.expand_path("../../lzma_sdk_wrapper", __dir__)

        case ::FFI::Platform::OS
        when "darwin"
          ext = "bundle"
        when "linux"
          ext = "so"
        when "windows"
          ext = "dll"
        else
          raise "Unsupported platform: #{::FFI::Platform::OS}"
        end

        lib_file = File.join(base_path, "lzma_sdk_wrapper.#{ext}")

        unless File.exist?(lib_file)
          raise LoadError, "Native extension not found at #{lib_file}. " \
                          "Run 'rake compile' to build the extension."
        end

        lib_file
      end

      # Load the compiled library
      ffi_lib library_path

      # Define callback types
      callback :progress_callback, [:uint64, :uint64, :pointer], :void
      callback :password_callback, [:pointer, :size_t, :pointer], :int

      # Archive operations
      attach_function :sz_open_archive, [:string, :int, :pointer], :pointer
      attach_function :sz_open_from_memory, [:pointer, :size_t, :int, :pointer], :pointer
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

      # Version info
      attach_function :sz_get_version, [], :string
      attach_function :sz_get_sdk_info, [], :string

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
