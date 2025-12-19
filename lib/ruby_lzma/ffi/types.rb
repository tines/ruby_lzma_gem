# frozen_string_literal: true

require "ffi"

module RubyLzma
  module FFI
    module Types
      extend ::FFI::Library

      # Entry information structure matching C struct SzEntryInfo
      class EntryInfo < ::FFI::Struct
        layout :name, [:char, 1024],
               :size, :uint64,
               :compressed_size, :uint64,
               :crc, :uint32,
               :modified_time, :uint64,
               :is_directory, :bool,
               :attributes, :uint32

        # Get entry name as Ruby string
        def name
          self[:name].to_ptr.read_string
        end

        # Check if entry is a directory
        def directory?
          self[:is_directory]
        end

        # Get entry size
        def size
          self[:size]
        end

        # Get compressed size
        def compressed_size
          self[:compressed_size]
        end

        # Get CRC checksum
        def crc
          self[:crc]
        end

        # Get modified time as Ruby Time object
        def modified_time
          timestamp = self[:modified_time]
          timestamp > 0 ? Time.at(timestamp) : nil
        end

        # Get file attributes
        def attributes
          self[:attributes]
        end
      end

      # Progress callback function signature
      # void (*progress_callback)(uint64_t completed, uint64_t total, void* user_data)
      callback :progress_callback, [:uint64, :uint64, :pointer], :void

      # Password callback function signature
      # int (*password_callback)(char* buffer, size_t buffer_size, void* user_data)
      callback :password_callback, [:pointer, :size_t, :pointer], :int
    end
  end
end
