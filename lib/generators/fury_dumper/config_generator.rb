# frozen_string_literal: true

module FuryDumper
  module Generators
    class ConfigGenerator < Rails::Generators::Base
      def self.gem_root
        File.expand_path('../../..', __dir__)
      end

      def self.source_root
        # Use the templates from the 2.3.x generator
        File.join(gem_root, 'rails_generators', 'fury_dumper_config', 'templates')
      end

      def generate
        template 'fury_dumper.rb', File.join('config', 'initializers', 'fury_dumper.rb')
        template 'fury_dumper.yml', File.join('config', 'fury_dumper.yml')
      end
    end
  end
end
