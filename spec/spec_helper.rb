# frozen_string_literal: true

require 'bundler/setup'
require 'fury_dumper'
require 'active_record'
require 'database_cleaner'

RSpec.configure do |config|
  ActiveRecord::Base.logger = Logger.new($stdout)
  ActiveRecord::Base.establish_connection(
    adapter: 'postgresql',
    database: ENV['POSTGRES_DB'] || 'fury_dumper_test',
    host: ENV['POSTGRES_HOST'] || 'localhost',
    port: ENV['POSTGRES_PORT'] || '5432',
    username: ENV['POSTGRES_USER'] || 'postgres',
    password: ENV['POSTGRES_PASSWORD'] || 'postgres'
  )

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end
end
