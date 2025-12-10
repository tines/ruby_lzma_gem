# frozen_string_literal: true

require "fileutils"
require "ruby_lzma"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Set up test fixtures path
  config.add_setting :fixtures_path
  config.fixtures_path = File.expand_path("fixtures", __dir__)

  # Helper to get fixture path
  config.before(:suite) do
    # Ensure fixtures directory exists
    FileUtils.mkdir_p(RSpec.configuration.fixtures_path)
  end
end

# Helper method to access fixtures
def fixture_path(filename)
  File.join(RSpec.configuration.fixtures_path, filename)
end
