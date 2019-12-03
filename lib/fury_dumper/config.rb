require 'yaml'

module FuryDumper
  class Config
    MODES = [:wide, :depth]

    def self.config
      @config || {}
    end

    def self.load(file)
      @config = ::YAML::load(file.respond_to?(:read) ? file : File.open(file))
      validate_config
    end

    def self.tables
      return @tables if @tables

      @tables = []
      relative_services&.each do |ms_name, ms_config|
        @tables += ms_config['tables'].keys
      end
      @tables
    end

    def self.batch_size
      @batch_size ||= (config['batch_size'] || 100).to_i
    end

    def self.limit
      batch_size * ratio_records_batches
    end

    def self.has_ms_relations?(table_name)
      tables.include?(table_name)
    end

    def self.is_exclude_relation?(relation_name)
      exclude_relations.include?(relation_name)
    end

    def self.mode
      if !@mode && MODES.include?(config['mode']&.to_sym)
        @mode ||= config['mode'].to_sym
      end

      @mode ||= :wide
    end

    def self.get_service_config(ms_name)
      relative_services[ms_name]
    end

    def self.relative_services
      config['relative_services']
    end

    def self.is_fast
      config['fast'] ? config['fast'].to_bool : true
    end

    private

    def self.validate_config
      return true unless relative_services

      relative_services.each do |ms_name, ms_config|
        check_presented(ms_config, "[#{ms_name}]")
        %w(database host port user password).each do |required_field|
          check_required_key(ms_config, required_field, "[#{ms_name}]")
        end

        check_presented(ms_config['tables'], "[#{ms_name}] tables")
        validate_tables_config(ms_config['tables'], ms_name)
      end

      true
    end

    def self.validate_tables_config(config, ms_name)
      config.each do |this_table, table_config|
        check_presented(table_config, "[#{ms_name}] -> #{this_table}")

        table_config.each do |ms_table, ms_table_config|
          check_presented(ms_table_config, "[#{ms_name}] -> #{this_table} -> #{ms_table}")

          %w(self_field_name ms_model_name ms_field_name).each do |required_field|
            check_required_key(ms_table_config, required_field, "[#{ms_name}] -> #{this_table} -> #{ms_table}")
          end

        end
      end
    end

    def self.check_presented(config, prefix)
      raise RuntimeError,
            "Configuration error! #{prefix} isn't describe" if config.blank?
    end

    def self.check_required_key(config, field, prefix)
      raise RuntimeError,
            "Configuration error! #{prefix} #{field} expected" unless config[field]
    end

    def self.ratio_records_batches
      @ratio_records_batches ||= (config['ratio_records_batches'] || 10).to_i
    end

    def self.exclude_relations
      @exclude_relations ||= config['exclude_relations']&.split(',')&.map(&:strip) || []
    end
  end
end
