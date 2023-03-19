# frozen_string_literal: true

class FuryDumperConfigGenerator < Rails::Generators::Base
  def manifest
    record do |m|
      m.template('fury_dumper.yml', 'config/fury_dumper.yml')
      m.template('fury_dumper.rb', 'config/fury_dumper.rb')
    end
  end
end
