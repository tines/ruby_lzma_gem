# frozen_string_literal: true

require "fileutils"
require "stringio"

module RubyLzma
  module Archive
    # Reader for extracting and reading archive files
    class Reader
      include Enumerable

      attr_reader :path

      # Default maximum size for a single entry extraction (1 GB)
      DEFAULT_MAX_ENTRY_SIZE = 1024 * 1024 * 1024

      # Default maximum total extraction size (10 GB)
      DEFAULT_MAX_TOTAL_SIZE = 10 * 1024 * 1024 * 1024

      # Default maximum compression ratio (10000:1)
      # LZMA2 legitimately achieves high ratios on repetitive data (1000-5000:1),
      # while actual archive bombs typically exceed 1,000,000:1.
      DEFAULT_MAX_COMPRESSION_RATIO = 10_000

      # Default maximum size for entries with unknown compression ratio (10 MB)
      # In solid archives, individual compressed_size may be 0 (unknown)
      DEFAULT_MAX_SIZE_UNKNOWN_RATIO = 10 * 1024 * 1024

      # Error raised when extraction limits are exceeded
      class ExtractionLimitError < RubyLzma::Error; end

      # Error raised when a path traversal attack is detected (alias for shared error)
      PathTraversalError = RubyLzma::Security::PathTraversalError

      class << self
        # Maximum allowed size for a single entry extraction (in bytes)
        # Set to nil to disable the limit
        attr_accessor :max_entry_size

        # Maximum allowed total extraction size (in bytes)
        # Set to nil to disable the limit
        attr_accessor :max_total_size

        # Maximum allowed compression ratio (uncompressed/compressed)
        # Set to nil to disable the limit
        attr_accessor :max_compression_ratio

        # Maximum allowed size for entries with unknown compression ratio (in bytes)
        # Applies to solid archives where compressed_size is 0
        # Set to nil to disable this check (falls back to max_entry_size only)
        attr_accessor :max_size_for_unknown_ratio
      end

      # Initialize class-level defaults
      self.max_entry_size = DEFAULT_MAX_ENTRY_SIZE
      self.max_total_size = DEFAULT_MAX_TOTAL_SIZE
      self.max_compression_ratio = DEFAULT_MAX_COMPRESSION_RATIO
      self.max_size_for_unknown_ratio = DEFAULT_MAX_SIZE_UNKNOWN_RATIO

      # Open an archive file for reading
      #
      # @param path [String] Path to the archive file
      # @param format [Integer] Archive format (default: auto-detect for 7z)
      # @param password [String, nil] Password for encrypted archives (optional)
      # @return [Reader] Reader instance
      # @raise [Error] if archive cannot be opened
      def initialize(path, format: FFI::Constants::SZ_FORMAT_7Z, password: nil)
        @path = File.expand_path(path)
        @format = format
        @password = password
        @handle = nil
        @entries = nil
        @closed = false

        open_archive
      end

      # Open an archive file and yield the reader, then automatically close
      #
      # @param path [String] Path to the archive file
      # @param format [Integer] Archive format
      # @param password [String, nil] Password for encrypted archives (optional)
      # @yield [reader] Yields the reader instance
      # @return [Object] Result of the block
      def self.open(path, format: FFI::Constants::SZ_FORMAT_7Z, password: nil)
        reader = new(path, format: format, password: password)
        return reader unless block_given?

        begin
          yield reader
        ensure
          reader.close
        end
      end

      # Open an archive from a memory buffer (StringIO or String)
      #
      # @param buffer [String, StringIO] Memory buffer containing archive data
      # @param format [Integer] Archive format
      # @param password [String, nil] Password for encrypted archives (optional)
      # @yield [reader] Yields the reader instance
      # @return [Object] Result of the block
      def self.open_buffer(buffer, format: FFI::Constants::SZ_FORMAT_7Z, password: nil)
        # Convert StringIO to String if needed
        data = buffer.is_a?(StringIO) ? buffer.string : buffer
        data = data.b if data.respond_to?(:b)  # Ensure binary encoding

        # Create memory pointer from string data
        buffer_ptr = ::FFI::MemoryPointer.new(:char, data.bytesize)
        buffer_ptr.put_bytes(0, data)

        error_ptr = FFI::Library.error_pointer
        handle = FFI::Library.sz_open_from_memory(buffer_ptr, data.bytesize, format, error_ptr)

        error_code = error_ptr.read_int
        FFI::Library.check_error(error_code)

        if handle.nil? || handle.null?
          raise Error, "Failed to open archive from memory"
        end

        # Create a reader instance with the handle
        reader = allocate
        reader.instance_variable_set(:@path, "<memory>")
        reader.instance_variable_set(:@format, format)
        reader.instance_variable_set(:@password, password)
        reader.instance_variable_set(:@handle, handle)
        reader.instance_variable_set(:@entries, nil)
        reader.instance_variable_set(:@closed, false)

        # Set password if provided
        if password
          result = FFI::Library.sz_set_password(handle, password)
          FFI::Library.check_error(result)
        end

        return reader unless block_given?

        begin
          yield reader
        ensure
          reader.close
        end
      end

      # Get the number of entries in the archive
      #
      # @return [Integer] Number of entries
      def size
        ensure_open
        entries.size
      end
      alias count size
      alias length size

      # Get all entries in the archive
      #
      # @return [Array<Entry>] Array of entries
      def entries
        ensure_open
        return @entries if @entries

        @entries = []
        entry_count = FFI::Library.sz_get_entry_count(@handle)

        entry_count.times do |i|
          info = FFI::Types::EntryInfo.new
          result = FFI::Library.sz_get_entry_info(@handle, i, info)
          FFI::Library.check_error(result)

          @entries << Entry.new(i, info)
        end

        @entries
      end

      # Iterate over all entries
      #
      # @yield [entry] Yields each entry
      def each(&block)
        entries.each(&block)
      end

      # Get entry by index
      #
      # @param index [Integer] Entry index
      # @return [Entry] Entry at the given index
      def [](index)
        entries[index]
      end

      # Extract a single entry to a file
      #
      # @param entry [Entry, Integer] Entry or entry index to extract
      # @param output_path [String] Path where the file should be extracted
      # @raise [Error] if extraction fails
      # @raise [ExtractionLimitError] if entry size exceeds limits
      # @raise [PathTraversalError] if output path escapes the target directory
      def extract(entry, output_path)
        ensure_open
        entry_obj = entry.is_a?(Entry) ? entry : entries[entry]
        index = entry_obj.index

        # Check extraction limits before proceeding
        check_extraction_limits(entry_obj)

        # Create parent directory if needed
        FileUtils.mkdir_p(File.dirname(output_path))

        result = FFI::Library.sz_extract_to_file(@handle, index, output_path)
        FFI::Library.check_error(result)
      end

      # Extract all entries to a directory
      #
      # @param output_dir [String] Directory where files should be extracted
      # @param full_paths [Boolean] Whether to preserve full paths (default: true)
      # @raise [ExtractionLimitError] if total extraction size exceeds limits
      # @raise [PathTraversalError] if any entry path would escape the output directory
      def extract_all(output_dir, full_paths: true)
        ensure_open
        base_dir = File.expand_path(output_dir)

        # Pre-check total size limit
        check_total_extraction_size(entries)

        entries.each do |entry|
          entry_path = entry.name
          entry_path = File.basename(entry_path) unless full_paths

          output_path = safe_extract_path(base_dir, entry_path)

          if entry.directory?
            FileUtils.mkdir_p(output_path)
          else
            # Check individual entry limits
            check_extraction_limits(entry)
            FileUtils.mkdir_p(File.dirname(output_path))
            result = FFI::Library.sz_extract_to_file(@handle, entry.index, output_path)
            FFI::Library.check_error(result)
          end
        end
      end

      # Extract an entry to memory
      #
      # @param entry [Entry, Integer] Entry or entry index to extract
      # @return [String] Extracted data as binary string
      # @raise [Error] if extraction fails
      # @raise [ExtractionLimitError] if entry size exceeds limits
      def extract_data(entry)
        ensure_open
        entry_obj = entry.is_a?(Entry) ? entry : entries[entry]
        index = entry_obj.index

        # Check extraction limits before proceeding
        check_extraction_limits(entry_obj)

        buffer_ptr = ::FFI::MemoryPointer.new(:pointer)
        size_ptr = ::FFI::MemoryPointer.new(:size_t)

        result = FFI::Library.sz_extract_to_memory(@handle, index, buffer_ptr, size_ptr)
        FFI::Library.check_error(result)

        buffer = buffer_ptr.read_pointer
        size = size_ptr.read_ulong

        # Read the data from C-allocated buffer
        data = buffer.read_bytes(size)

        # Free the C-allocated buffer (allocated with malloc in the C library)
        FFI::Library.sz_free(buffer) unless buffer.null?

        data
      end

      # Test archive validity (verify integrity and password if encrypted)
      #
      # @return [Boolean] true if archive is valid, false otherwise
      def test
        ensure_open
        result = FFI::Library.sz_verify(@handle)
        result == FFI::Constants::SZW_OK
      end

      # Check if the archive is closed
      #
      # @return [Boolean] true if closed
      def closed?
        @closed
      end

      # Close the archive
      def close
        return if @closed

        if @handle && !@handle.null?
          result = FFI::Library.sz_close_archive(@handle)
          FFI::Library.check_error(result) if result != FFI::Constants::SZW_OK
        end

        @handle = nil
        @entries = nil
        @closed = true
      end

      # Get string representation
      def to_s
        "#<RubyLzma::Archive::Reader path=#{@path} entries=#{size}>"
      end

      def inspect
        to_s
      end

      private

      # Check extraction limits for a single entry
      #
      # @param entry [Entry] The entry to check
      # @raise [ExtractionLimitError] if limits are exceeded
      def check_extraction_limits(entry)
        max_size = self.class.max_entry_size
        max_ratio = self.class.max_compression_ratio

        # Check uncompressed size limit
        if max_size && entry.size > max_size
          raise ExtractionLimitError,
                "Entry '#{entry.name}' uncompressed size (#{format_size(entry.size)}) " \
                "exceeds maximum allowed size (#{format_size(max_size)}). " \
                "Set RubyLzma::Archive::Reader.max_entry_size = nil to disable this limit."
        end

        # Check compression ratio (potential archive bomb)
        if max_ratio
          if entry.compressed_size > 0
            ratio = entry.size.to_f / entry.compressed_size
            if ratio > max_ratio
              raise ExtractionLimitError,
                    "Entry '#{entry.name}' has suspicious compression ratio (#{ratio.round(1)}:1). " \
                    "Maximum allowed ratio is #{max_ratio}:1. This may indicate an archive bomb. " \
                    "Set RubyLzma::Archive::Reader.max_compression_ratio = nil to disable this limit."
            end
          elsif entry.size > 0
            # compressed_size is 0 but entry has non-zero size - this can happen with solid archives
            # Treat as potentially infinite ratio (unknown compression) - reject if entry is large
            max_unknown = self.class.max_size_for_unknown_ratio
            if max_unknown && entry.size >= max_unknown
              raise ExtractionLimitError,
                    "Entry '#{entry.name}' has unknown compression ratio (compressed size unavailable) " \
                    "and large uncompressed size (#{format_size(entry.size)}). Maximum allowed is #{format_size(max_unknown)}. " \
                    "This may indicate an archive bomb. " \
                    "Set RubyLzma::Archive::Reader.max_size_for_unknown_ratio = nil to disable this limit."
            end
          end
        end
      end

      # Check total extraction size limit
      #
      # @param entries [Array<Entry>] The entries to check
      # @raise [ExtractionLimitError] if total size exceeds limit
      def check_total_extraction_size(entries)
        max_total = self.class.max_total_size
        return unless max_total

        total_size = entries.sum(&:size)
        if total_size > max_total
          raise ExtractionLimitError,
                "Total uncompressed size (#{format_size(total_size)}) exceeds " \
                "maximum allowed total size (#{format_size(max_total)}). " \
                "Set RubyLzma::Archive::Reader.max_total_size = nil to disable this limit."
        end
      end

      # Safely join a base directory with a relative path, preventing path traversal
      # Delegates to the shared Security module
      #
      # @param base_dir [String] The base directory (must be absolute)
      # @param relative_path [String] The relative path from the archive
      # @return [String] The safe, absolute output path
      # @raise [PathTraversalError] if the path would escape the base directory
      def safe_extract_path(base_dir, relative_path)
        RubyLzma::Security.safe_extract_path(base_dir, relative_path)
      end

      # Format a size in bytes to a human-readable string
      def format_size(bytes)
        units = %w[B KB MB GB TB]
        unit_index = 0
        size = bytes.to_f

        while size >= 1024 && unit_index < units.length - 1
          size /= 1024
          unit_index += 1
        end

        "#{size.round(2)} #{units[unit_index]}"
      end

      def open_archive
        raise Error, "File not found: #{@path}" unless File.exist?(@path)

        error_ptr = FFI::Library.error_pointer
        @handle = FFI::Library.sz_open_archive(@path, @format, error_ptr)

        error_code = error_ptr.read_int
        FFI::Library.check_error(error_code)

        if @handle.nil? || @handle.null?
          raise Error, "Failed to open archive: #{@path}"
        end

        # Set password if provided
        if @password
          result = FFI::Library.sz_set_password(@handle, @password)
          FFI::Library.check_error(result)
        end
      end

      def ensure_open
        raise Error, "Archive is closed" if @closed
      end
    end
  end
end
