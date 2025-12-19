# frozen_string_literal: true

require "fileutils"

module RubyLzma
  module Archive
    # Reader for extracting and reading archive files
    class Reader
      include Enumerable

      attr_reader :path

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
      def extract(entry, output_path)
        ensure_open
        index = entry.is_a?(Entry) ? entry.index : entry

        # Create parent directory if needed
        FileUtils.mkdir_p(File.dirname(output_path))

        result = FFI::Library.sz_extract_to_file(@handle, index, output_path)
        FFI::Library.check_error(result)
      end

      # Extract all entries to a directory
      #
      # @param output_dir [String] Directory where files should be extracted
      # @param full_paths [Boolean] Whether to preserve full paths (default: true)
      def extract_all(output_dir, full_paths: true)
        ensure_open
        base_dir = File.expand_path(output_dir)

        entries.each do |entry|
          entry_path = entry.name
          entry_path = File.basename(entry_path) unless full_paths

          output_path = safe_extract_path(base_dir, entry_path)

          if entry.directory?
            FileUtils.mkdir_p(output_path)
          else
            extract(entry, output_path)
          end
        end
      end

      # Extract an entry to memory
      #
      # @param entry [Entry, Integer] Entry or entry index to extract
      # @return [String] Extracted data as binary string
      # @raise [Error] if extraction fails
      def extract_data(entry)
        ensure_open
        index = entry.is_a?(Entry) ? entry.index : entry

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

      def safe_extract_path(base_dir, entry_path)
        cleaned = entry_path.to_s.gsub(/\A[\/\\]+/, "")
        full_path = File.expand_path(File.join(base_dir, cleaned))

        unless full_path.start_with?("#{base_dir}/") || full_path == base_dir
          raise Error, "Unsafe path in archive: #{entry_path}"
        end

        full_path
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
