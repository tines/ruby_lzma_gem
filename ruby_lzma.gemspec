# frozen_string_literal: true

require_relative "lib/ruby_lzma/version"

Gem::Specification.new do |spec|
  spec.name = "ruby_lzma"
  spec.version = RubyLzma::VERSION
  spec.authors = ["Joseph Korany"]
  spec.email = ["jkorany@tines.io"]

  spec.summary = "Ruby bindings for LZMA SDK (7-Zip) with password support and memory operations"
  spec.description = <<~DESC
    A Ruby gem providing native bindings to the LZMA SDK (7-Zip) for high-performance archive operations.
    Features include full password-protected archive support (currently only for reading),
    memory buffer operations (StringIO/String), archive verification, and RBS type signatures.
  DESC
  spec.homepage = "https://github.com/tines/ruby_lzma_gem"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  # spec.metadata["documentation_uri"] = "https://rubydoc.info/gems/ruby_lzma"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[
          bin/
          test/
          spec/
          features/
          benchmark/
          examples/
          tmp/
          .git
          .github
          .vscode
          .idea
          appveyor
          Gemfile
        ])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/lzma_sdk_wrapper/extconf.rb"]

  # Runtime dependencies
  spec.add_dependency "ffi", "~> 1.15"

  # Development dependencies
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rake-compiler", "~> 1.2"
  spec.add_development_dependency "rspec", "~> 3.12"
end
