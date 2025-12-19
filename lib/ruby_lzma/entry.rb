# frozen_string_literal: true

module RubyLzma
  # Represents a single entry (file or directory) in an archive
  class Entry
    attr_reader :index, :name, :size, :compressed_size, :crc, :modified_time, :attributes

    # Alias for compatibility with seven_zip_ruby gem
    alias path name

    def initialize(index, info)
      @index = index
      @name = info.name
      @size = info.size
      @compressed_size = info.compressed_size
      @crc = info.crc
      @modified_time = info.modified_time
      @attributes = info.attributes
      @is_directory = info.directory?
    end

    # Check if entry is a directory
    def directory?
      @is_directory
    end

    # Check if entry is a file
    def file?
      !@is_directory
    end

    # Get compression ratio as a percentage
    def compression_ratio
      return 0.0 if @size.zero?
      (1.0 - (@compressed_size.to_f / @size.to_f)) * 100.0
    end

    # String representation
    def to_s
      type = directory? ? "DIR " : "FILE"
      "#{type} #{name} (#{size} bytes)"
    end

    def inspect
      "#<RubyLzma::Entry:#{object_id} #{to_s}>"
    end
  end
end
