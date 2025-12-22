# frozen_string_literal: true

module RubyLzma
  # Security utilities shared across Reader and Writer
  module Security
    # Error raised when a path traversal attack is detected
    class PathTraversalError < RubyLzma::Error; end

    # Sanitize an archive path to prevent Zip Slip (directory traversal) attacks
    #
    # This method ensures that paths written into or extracted from archives
    # cannot be used to write/read files outside the intended directory.
    #
    # @param path [String] The archive path to sanitize
    # @return [String] The sanitized path
    # @raise [PathTraversalError] if the path contains traversal sequences
    def self.sanitize_path(path)
      return path if path.nil?

      # Convert to string and normalize separators to forward slashes
      normalized = path.to_s.tr("\\", "/")

      # Check for null bytes (path injection)
      if normalized.include?("\x00")
        raise PathTraversalError, "Path contains null bytes: #{path.inspect}"
      end

      # Reject paths with parent directory references
      # Split and check each component to catch encoded or tricky variations
      components = normalized.split("/")
      components.each do |component|
        if component == ".."
          raise PathTraversalError,
                "Path contains directory traversal sequence '..': #{path.inspect}"
        end
      end

      # Also check for .. in the raw path (catches URL-encoded or other tricks)
      if normalized.include?("..") || normalized =~ /\.\./
        raise PathTraversalError,
              "Path contains directory traversal sequence: #{path.inspect}"
      end

      # Reject absolute paths (Unix or Windows style)
      if normalized.start_with?("/") || normalized =~ /\A[A-Za-z]:/
        raise PathTraversalError,
              "Path must be relative, not absolute: #{path.inspect}"
      end

      # Remove leading ./ if present (normalize but don't reject)
      normalized = normalized.sub(%r{\A\./+}, "")

      # Remove any leading slashes that might remain
      normalized = normalized.sub(%r{\A/+}, "")

      # Collapse multiple consecutive slashes
      normalized = normalized.gsub(%r{/+}, "/")

      # Remove trailing slashes (except for empty string)
      normalized = normalized.chomp("/") unless normalized.empty?

      # Final validation: the path should not be empty after sanitization
      if normalized.empty?
        raise PathTraversalError, "Path cannot be empty after sanitization"
      end

      normalized
    end

    # Safely join a base directory with a relative path, preventing path traversal
    #
    # @param base_dir [String] The base directory (should be absolute)
    # @param relative_path [String] The relative path from the archive
    # @return [String] The safe, absolute output path
    # @raise [PathTraversalError] if the path would escape the base directory
    def self.safe_extract_path(base_dir, relative_path)
      # Normalize the relative path (convert backslashes, handle edge cases)
      normalized = relative_path.to_s.tr("\\", "/")

      # Check for null bytes
      if normalized.include?("\x00")
        raise PathTraversalError,
              "Entry path contains null bytes: #{relative_path.inspect}"
      end

      # Construct the full path
      full_path = File.expand_path(File.join(base_dir, normalized))

      # Ensure the full path is within the base directory
      # Add trailing separator to base_dir for accurate prefix matching
      base_with_sep = base_dir.end_with?(File::SEPARATOR) ? base_dir : "#{base_dir}#{File::SEPARATOR}"

      unless full_path.start_with?(base_with_sep) || full_path == base_dir
        raise PathTraversalError,
              "Entry path '#{relative_path}' would extract outside the target directory. " \
              "This may indicate a Zip Slip attack."
      end

      full_path
    end
  end
end

