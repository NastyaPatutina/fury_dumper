# frozen_string_literal: true

require_relative 'lib/fury_dumper/version'

Gem::Specification.new do |spec|
  spec.name          = 'fury_dumper'
  spec.version       = FuryDumper::VERSION
  spec.authors       = ['Nastya Patutina']
  spec.email         = ['npatutina@gmail.con']

  spec.summary       = 'Simple dump for main service and other microservices'
  spec.description   = 'Dump from remote DB by lead_ids interval'
  spec.homepage      = 'https://github.com/NastyaPatutina/fury_dumper'
  spec.required_ruby_version = Gem::Requirement.new('>= 2.3.0') # rubocop:disable Gemspec/RequiredRubyVersion

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/NastyaPatutina/fury_dumper'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.0'

  spec.add_runtime_dependency 'highline', '~> 1.6'
  spec.add_runtime_dependency 'httpclient', '~> 2.8'
  spec.add_runtime_dependency 'pg', '~> 1.4'
  spec.add_runtime_dependency 'rails', '>= 4.0.13'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
