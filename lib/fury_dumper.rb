# frozen_string_literal: true

require 'rails'
require 'fury_dumper/version'
require 'fury_dumper/config'
require 'fury_dumper/engine'
require 'fury_dumper/dumper'
require 'fury_dumper/api'
require 'fury_dumper/dumpers/relation_items'
require 'fury_dumper/dumpers/dump_state'
require 'fury_dumper/dumpers/model_queue'
require 'fury_dumper/dumpers/model'
require 'fury_dumper/encrypter'
require 'httpclient'
require 'highline/import'

module FuryDumper
  class Error < StandardError
  end

  def self.configuration
    @configuration ||= Config.config
  end

  # Start dumping
  #
  # @param password[String]           - password for remote DB
  # @param host[String]               - host for remote DB
  # @param port[String]               - port for remote DB
  # @param user[String]               - username for remote DB
  # @param model_name[String]         - name of model for dump
  # @param field_name[String]         - field name for model
  # @param field_values[Array|Range]  - values of field_name
  # @param database[String]           - DB remote name
  # @param debug_mode[Symbol]         - debug mode (full - all msgs, short - part of msgs, none -  nothing)
  # @param ask[Boolean]               - ask user for confirm different schema of target & remote DB
  #
  # @example FuryDumper.dump( password:     '12345',
  #                             host:         'localhost',
  #                             port:         '5432',
  #                             user:         'username',
  #                             model_name:   'User',
  #                             field_name:   'admin_token',
  #                             field_values: ['99999999-8888-4444-1212-111111111111'],
  #                             database:     'staging',
  #                             debug_mode:   :short)
  def self.dump(password:,
                host:,
                port:,
                user:,
                field_values:, database:, model_name: 'Lead',
                field_name: 'id',
                debug_mode: :none,
                ask: true)

    check_type(model_name, String, 'model name')
    check_type(field_name, String, 'field name')
    check_type(field_values, [Array, Range], 'field values')

    states = []
    field_values.to_a.in_groups_of(FuryDumper::Config.batch_size) do |batch|
      relation_items = FuryDumper::Dumpers::RelationItems.new_with_key_value(item_key: field_name, item_values: batch)

      sync = Dumper.new \
        password: password,
        host: host,
        port: port,
        user: user,
        database: database,
        model: FuryDumper::Dumpers::Model.new(source_model: model_name, relation_items: relation_items),
        debug_mode: debug_mode

      if ask && !sync.equal_schemas?
        confirm = ask('Are you sure to continue? [Y/N] ') { |yn| yn.limit = 1, yn.validate = /[yn]/i }
        ask     = false
        return unless confirm.downcase == 'y' # rubocop:disable Lint/NonLocalExitFromIterator
      end

      sync.sync_models
      states << sync.dump_state
    end

    states.each_with_index do |state, index|
      p "Batch ##{index}:"
      state.print_statistic
    end
    true
  end

  def self.check_type(field, expected_type, field_name)
    is_ok     = if expected_type.is_a?(Array)
                  expected_type.any? do |type|
                    field.is_a?(type)
                  end
                else
                  field.is_a?(expected_type)
                end
    types_str = expected_type.is_a?(Array) ? expected_type.join(' or ') : expected_type

    raise ArgumentError, "Expected #{field_name} as #{types_str}, got: #{field.class}" unless is_ok
  end
end
