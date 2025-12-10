# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rake/clean"

CLEAN.include("ext/lzma_sdk_wrapper/*.o")
CLEAN.include("ext/lzma_sdk_wrapper/*.bundle")
CLEAN.include("ext/lzma_sdk_wrapper/*.so")
CLEAN.include("ext/lzma_sdk_wrapper/*.dll")
CLEAN.include("ext/lzma_sdk_wrapper/Makefile")
CLEAN.include("ext/lzma_sdk_wrapper/mkmf.log")
CLEAN.include("ext/lzma_sdk_wrapper/*.dSYM/")
CLEAN.include("lib/lzma_sdk_wrapper")
CLEAN.include("benchmark/fixtures/**")
CLEAN.include("benchmark/output/**")

# Compile task for the native extension
task :compile do
  Dir.chdir("ext/lzma_sdk_wrapper") do
    ruby "extconf.rb"
    sh "make"
  end

  # Copy the compiled library to lib/
  FileUtils.mkdir_p("lib/lzma_sdk_wrapper")
  ext_file = Dir["ext/lzma_sdk_wrapper/*.{bundle,so,dll}"].first
  if ext_file
    FileUtils.cp(ext_file, "lib/lzma_sdk_wrapper/")
    puts "Copied #{ext_file} to lib/lzma_sdk_wrapper/"
  else
    warn "Warning: No compiled library found"
  end
end

RSpec::Core::RakeTask.new(:spec)

# Make compile run before spec
task spec: :compile

task default: :spec
