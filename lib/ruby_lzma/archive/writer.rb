# frozen_string_literal: true

require "fileutils"

module RubyLzma
  module Archive
    # Writer for creating new archive files
    class Writer
      attr_reader :path

      # Compression methods
      METHOD_LZMA = FFI::Constants::SZ_METHOD_LZMA
      METHOD_LZMA2 = FFI::Constants::SZ_METHOD_LZMA2
      METHOD_PPMD = FFI::Constants::SZ_METHOD_PPMD
      METHOD_BZIP2 = FFI::Constants::SZ_METHOD_BZIP2
      METHOD_DEFLATE = FFI::Constants::SZ_METHOD_DEFLATE

      # Compression levels
      LEVEL_STORE = FFI::Constants::SZ_LEVEL_STORE
      LEVEL_FASTEST = FFI::Constants::SZ_LEVEL_FASTEST
      LEVEL_FAST = FFI::Constants::SZ_LEVEL_FAST
      LEVEL_NORMAL = FFI::Constants::SZ_LEVEL_NORMAL
      LEVEL_MAXIMUM = FFI::Constants::SZ_LEVEL_MAXIMUM
      LEVEL_ULTRA = FFI::Constants::SZ_LEVEL_ULTRA

      # Error raised when a path traversal attack is detected (alias for shared error)
      PathTraversalError = RubyLzma::Security::PathTraversalError

      # Create a new archive for writing
      #
      # @param path [String] Path to the archive file to create
      # @param format [Integer] Archive format (default: 7z)
      # @param password [String, nil] Password for encryption (optional)
      # @param method [Integer] Compression method (default: LZMA2)
      # @param level [Integer] Compression level (default: NORMAL)
      # @param solid [Boolean] Use solid compression (default: true)
      # @return [Writer] Writer instance
      # @raise [Error] if archive cannot be created
      def initialize(path, format: FFI::Constants::SZ_FORMAT_7Z, password: nil,
                     method: METHOD_LZMA2, level: LEVEL_NORMAL, solid: true)
        @path = File.expand_path(path)
        @format = format
        @password = password
        @handle = nil
        @closed = false
        @entries = []

        # Build compression options
        @options = FFI::Types::CompressionOptions.new
        @options[:method] = method
        @options[:level] = level
        @options[:threads] = 0  # Auto-detect
        @options[:dictionary_size] = 0  # Default
        @options[:solid] = solid

        create_archive
      end

      # Open an archive for writing and yield the writer, then automatically close
      #
      # @param path [String] Path to the archive file to create
      # @param format [Integer] Archive format
      # @param password [String, nil] Password for encryption (optional)
      # @param method [Integer] Compression method
      # @param level [Integer] Compression level
      # @param solid [Boolean] Use solid compression
      # @yield [writer] Yields the writer instance
      # @return [Object] Result of the block
      def self.open(path, format: FFI::Constants::SZ_FORMAT_7Z, password: nil,
                    method: METHOD_LZMA2, level: LEVEL_NORMAL, solid: true)
        writer = new(path, format: format, password: password,
                     method: method, level: level, solid: solid)
        return writer unless block_given?

        begin
          yield writer
        ensure
          writer.close
        end
      end

      # Add a file from disk to the archive
      #
      # @param src_path [String] Path to the source file on disk
      # @param archive_path [String, nil] Path within the archive (defaults to filename)
      # @raise [Error] if file cannot be added
      # @raise [PathTraversalError] if archive_path contains path traversal sequences
      def add_file(src_path, archive_path = nil)
        ensure_open
        src_path = File.expand_path(src_path)

        raise Error, "File not found: #{src_path}" unless File.exist?(src_path)
        raise Error, "Cannot add directory with add_file, use add_directory instead" if File.directory?(src_path)

        # Default archive path to just the filename, then sanitize
        archive_path ||= File.basename(src_path)
        archive_path = sanitize_archive_path(archive_path)

        result = FFI::Library.sz_add_file(@handle, src_path, archive_path)
        FFI::Library.check_error(result)

        @entries << archive_path
      end

      # Add a directory recursively to the archive
      #
      # @param src_path [String] Path to the source directory on disk
      # @param archive_path [String, nil] Path prefix within the archive (defaults to directory name)
      # @raise [Error] if directory cannot be added
      # @raise [PathTraversalError] if archive_path contains path traversal sequences
      def add_directory(src_path, archive_path = nil)
        ensure_open
        src_path = File.expand_path(src_path)

        raise Error, "Directory not found: #{src_path}" unless File.exist?(src_path)
        raise Error, "Not a directory: #{src_path}" unless File.directory?(src_path)

        # Default archive path to just the directory name, then sanitize
        archive_path ||= File.basename(src_path)
        archive_path = sanitize_archive_path(archive_path)

        result = FFI::Library.sz_add_directory(@handle, src_path, archive_path)
        FFI::Library.check_error(result)

        @entries << archive_path
      end

      # Add data from memory to the archive
      #
      # @param data [String] Binary data to add
      # @param archive_path [String] Path within the archive
      # @raise [Error] if data cannot be added
      # @raise [PathTraversalError] if archive_path contains path traversal sequences
      def add_data(data, archive_path)
        ensure_open

        raise Error, "Archive path is required" if archive_path.nil? || archive_path.empty?

        # Sanitize archive path to prevent Zip Slip attacks
        archive_path = sanitize_archive_path(archive_path)

        # Ensure binary encoding
        data = data.b if data.respond_to?(:b)

        # Create memory pointer from string data
        buffer_ptr = ::FFI::MemoryPointer.new(:char, data.bytesize)
        buffer_ptr.put_bytes(0, data)

        result = FFI::Library.sz_add_data(@handle, buffer_ptr, data.bytesize, archive_path)
        FFI::Library.check_error(result)

        @entries << archive_path
      end

      # Create an empty directory in the archive
      #
      # @param archive_path [String] Directory path within the archive
      # @raise [Error] if directory cannot be created
      # @raise [PathTraversalError] if archive_path contains path traversal sequences
      def mkdir(archive_path)
        ensure_open

        raise Error, "Archive path is required" if archive_path.nil? || archive_path.empty?

        # Sanitize archive path to prevent Zip Slip attacks
        archive_path = sanitize_archive_path(archive_path)

        result = FFI::Library.sz_mkdir(@handle, archive_path)
        FFI::Library.check_error(result)

        @entries << archive_path
      end

      # Get the number of entries added to the archive
      #
      # @return [Integer] Number of entries
      def size
        @entries.size
      end
      alias count size
      alias length size

      # Check if the archive is closed
      #
      # @return [Boolean] true if closed
      def closed?
        @closed
      end

      # Close the archive (finalizes writing)
      def close
        return if @closed

        if @handle && !@handle.null?
          result = FFI::Library.sz_close_archive(@handle)
          if result != FFI::Constants::SZW_OK
            @handle = nil
            @closed = true
            # Get error message from the constants
            msg = FFI::Constants::ERROR_MESSAGES[result] || "Archive close failed (code: #{result})"
            raise Error, msg
          end
        end

        @handle = nil
        @closed = true
      end

      # Get string representation
      def to_s
        status = @closed ? "closed" : "open"
        "#<RubyLzma::Archive::Writer path=#{@path} entries=#{size} status=#{status}>"
      end

      def inspect
        to_s
      end

      private

      # Sanitize archive path to prevent Zip Slip (directory traversal) attacks
      # Delegates to the shared Security module
      #
      # @param path [String] The archive path to sanitize
      # @return [String] The sanitized path
      # @raise [PathTraversalError] if the path contains traversal sequences
      def sanitize_archive_path(path)
        RubyLzma::Security.sanitize_path(path)
      end

      def create_archive
        # Ensure parent directory exists
        FileUtils.mkdir_p(File.dirname(@path))

        @handle = FFI::Library.sz_create_archive(@path, @format, @options)

        if @handle.nil? || @handle.null?
          raise Error, "Failed to create archive: #{@path}"
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

