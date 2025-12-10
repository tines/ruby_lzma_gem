# frozen_string_literal: true

RSpec.describe RubyLzma do
  it "has a version number" do
    expect(RubyLzma::VERSION).not_to be nil
  end

  it "provides FFI library" do
    expect(RubyLzma::FFI::Library).to be_a(Module)
  end

  it "provides Archive::Reader class" do
    expect(RubyLzma::Archive::Reader).to be_a(Class)
  end

  it "provides Entry class" do
    expect(RubyLzma::Entry).to be_a(Class)
  end

  it "provides error classes" do
    expect(RubyLzma::Error).to be < StandardError
  end
end
