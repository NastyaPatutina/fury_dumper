# frozen_string_literal: true

module FuryDumper
  class Dumper
    attr_reader :dump_state

    def initialize(password:,
                   host:,
                   port:,
                   user:,
                   database:,
                   model:,
                   debug_mode:)

      @password =       password
      @host =           host
      @user =           user
      @database =       database
      @port =           port
      @model =          model
      @debug_mode =     debug_mode
      @dump_state =     Dumpers::DumpState.new(root_source_model: @model_name)
      @undump_models =  []
    end

    def sync_models
      p '--- Dump models ---'
      if FuryDumper::Config.mode == :wide
        sync_model_in_wight(@model)
      else
        sync_model_in_depth(@model)
      end

      @dump_state.stop
      print_undump_models
    end

    def equal_schemas?
      tables_list   = cur_connection.tables.map { |e| "'#{e}'" }.join(', ')
      sql           = 'SELECT column_name, data_type, table_name FROM INFORMATION_SCHEMA.COLUMNS ' \
                      "WHERE table_name IN (#{tables_list});"
      cur_schema    = cur_connection.exec_query(sql).to_a
      remote_schema = remote_connection.exec_query(sql).to_a
      difference    = difference(remote_schema, cur_schema)

      if difference.present?
        difference.group_by { |e| e['table_name'] }.each do |table_name, diff|
          p "💣 Found difference for table #{table_name}"
          diff.sort_by { |e| e['column_name'] }.each do |dif|
            if cur_schema.include?(dif)
              p "Current DB have column: #{dif['column_name']} <#{dif['data_type']}>"
            else
              p "Remote DB  have column: #{dif['column_name']} <#{dif['data_type']}>"
            end
          end
        end
        false
      else
        true
      end
    end

    private

    def sync_model_in_depth(model)
      print "Start #{model.to_short_str} dump", model.iteration if full_debug_mode?
      active_record_model = model.active_record_model
      return if relation_already_exist?(model, @dump_state)

      # Добавляем в список моделей, которые уже стащили
      @dump_state.add_loaded_relation(model)

      buffer = model.to_full_str

      return unless dump_model(model)

      send_out_ms_dump(current_model)

      return if empty_active_record?(model, buffer)

      print buffer, model.iteration

      active_record_model.reflect_on_all_associations.each do |relation|
        # Проверка на корректную связь
        next unless valid_relation?(relation, model)

        # Исключения
        next if excluded?(model, relation)

        # Игнорим through
        next if through?(relation, model.iteration)

        # Если связана с полиморфной сущностью ...
        new_models = build_polymorphic_models(model, relation)
        unless new_models.nil?
          new_models.each do |new_model|
            sync_model_in_depth(new_model)
          end

          next
        end

        # Игнорим связи для другой БД
        next if other_db?(relation, model.iteration)

        print_new_model(model, relation)

        new_model = build_as_models(model, relation, @dump_state) ||
                    build_default_model(model, relation, @dump_state)

        next if new_model.nil?

        sync_model_in_depth(new_model)
      end

      log_model_warnings(model)
      true
    end

    def sync_model_in_wight(model, model_queue = Dumpers::ModelQueue.new)
      print "Start #{model.to_short_str} dump", model.iteration if full_debug_mode?
      model_queue.add_element(model: model, dump_state: @dump_state)

      until model_queue.empty?
        current_model, dump_state = model_queue.fetch_element
        if full_debug_mode?
          print "Relation #{current_model.to_short_str} start dump (queue size - #{model_queue.count})",
                current_model.iteration
        end

        active_record_model = current_model.active_record_model
        next if relation_already_exist?(current_model, dump_state)

        # Добавляем в список моделей, которые уже стащили
        dump_state.add_loaded_relation(current_model)

        buffer = current_model.to_full_str
        next unless dump_model(current_model)

        send_out_ms_dump(current_model)

        next if empty_active_record?(current_model, buffer)

        print buffer, current_model.iteration

        active_record_model.reflect_on_all_associations.each do |relation|
          # Проверка на корректную связь
          next unless valid_relation?(relation, current_model)

          # Исключения
          next if excluded?(current_model, relation)

          # Игнорим through
          next if through?(relation, current_model.iteration)

          # Если связана с полиморфной сущностью ...
          new_models = build_polymorphic_models(current_model, relation)
          unless new_models.nil?
            new_models.each do |new_model|
              next if new_model.nil?

              model_queue.add_element(model: new_model, dump_state: dump_state)
            end

            next
          end
          print_new_model(current_model, relation)

          # Игнорим связи для другой БД
          next if other_db?(relation, current_model.iteration)

          new_model = build_as_models(current_model, relation, dump_state) ||
                      build_default_model(current_model, relation, dump_state)

          next if new_model.nil?

          print "Relation #{new_model.to_short_str} add to queue", current_model.iteration if full_debug_mode?
          model_queue.add_element(model: new_model, dump_state: dump_state)
        end

        log_model_warnings(model)
      end
    end

    def build_default_model(current_model, relation, dump_state)
      relation_class      = relation.klass.to_s
      self_field_name     = self_field_name(current_model, relation)
      relation_field_name = relation_field_name(relation, current_model.iteration).to_s

      new_model = Dumpers::Model.new(source_model: relation_class,
                                     relation_items: Dumpers::RelationItems.new_with_key_value(
                                       item_key: relation_field_name,
                                       item_values: []
                                     ),
                                     iteration: current_model.next_iteration,
                                     root_model: current_model.root_model)

      # Связь с другой таблицей уже была
      return nil if relation_already_exist?(new_model, dump_state)

      relation_values = if relation.macro == :has_and_belongs_to_many
                          # Get association foreign values for has_and_belongs_to_many relation
                          active_record_has_and_belongs_to_many(current_model, relation).presence
                        else
                          attribute_values(current_model.to_active_record_relation, self_field_name)
                        end

      return nil if relation_values.compact.empty?

      items = [Dumpers::RelationItem.new(key: relation_field_name, values_for_key: relation_values)]

      # Если связь со scope, получить все условия
      items += fetch_scope_items(current_model, relation)

      new_model.relation_items = Dumpers::RelationItems.new_with_items(items: items)

      new_model
    end

    # Get association foreign values for has_and_belongs_to_many relation
    # @return [Array of String] association foreign values
    def active_record_has_and_belongs_to_many(model, relation)
      return [] unless relation.macro == :has_and_belongs_to_many

      dump_proxy_table(model, relation)
    end

    def build_polymorphic_models(current_model, relation)
      return nil unless relation.options[:polymorphic]

      active_record_values  = current_model.to_active_record_relation
      relation_foreign_key  = relation.foreign_key
      polymorphic_models    = attribute_values(active_record_values, relation.foreign_type)

      print "Found polymorphic relation #{current_model.source_model}(#{relation.name}): " \
            "#{polymorphic_models.join(', ')}", current_model.iteration

      polymorphic_models.map do |polymorphic_model|
        next unless polymorphic_model
        next unless validate_model_by_name(polymorphic_model, current_model.iteration)

        polymorphic_primary_key = polymorphic_model.constantize.primary_key.to_s
        type_values             = { relation.foreign_type => polymorphic_model }
        polymorphic_values      = attribute_values(active_record_values.where(type_values), relation_foreign_key)

        Dumpers::Model.new(source_model: polymorphic_model,
                           relation_items: Dumpers::RelationItems.new_with_key_value(item_key: polymorphic_primary_key,
                                                                                     item_values: polymorphic_values),
                           iteration: current_model.next_iteration,
                           root_model: current_model.root_model)
      end
    end

    def build_as_models(current_model, relation, dump_state)
      return nil unless relation.options[:as]

      relation_class      = relation.klass.to_s
      self_field_name     = self_field_name(current_model, relation)
      relation_field_name = relation_field_name(relation, current_model.iteration).to_s

      new_model = Dumpers::Model.new(source_model: relation_class,
                                     relation_items: Dumpers::RelationItems.new_with_key_value(
                                       item_key: relation_field_name,
                                       item_values: []
                                     ),
                                     iteration: current_model.next_iteration,
                                     root_model: current_model.root_model)

      print "Add source for #{current_model.source_model}(#{relation.name})", current_model.iteration

      active_record_values  = current_model.to_active_record_relation
      relation_field_values = attribute_values(active_record_values, self_field_name)

      items = [Dumpers::RelationItem.new(key: relation_field_name, values_for_key: relation_field_values),
               Dumpers::RelationItem.new(key: relation.type, values_for_key: [current_model.source_model],
                                         additional: true)]

      new_model.relation_items  = Dumpers::RelationItems.new_with_items(items: items)
      new_model.root_model      = current_model

      # Связь с другой таблицей уже была
      return nil if relation_already_exist?(new_model, dump_state)

      new_model
    end

    def self_field_name(current_model, relation)
      relation_foreign_key = relation.foreign_key
      relation_primary_key = relation.options[:primary_key]

      case relation.macro
      when :belongs_to
        # Связь в этой таблице - получить нужные id = вытянуть значения
        relation_foreign_key
      when :has_many, :has_one
        # Связь с другой таблице - получить где relation_foreign_key = текущие значения
        (relation_primary_key || current_model.primary_key).to_s
      when :has_and_belongs_to_many
        'id'
      else
        print "Unknown macro in relation #{relation.macro}", current_model.iteration
      end
    end

    def relation_field_name(relation, iteration)
      relation_foreign_key = relation.foreign_key
      relation_primary_key = relation.options[:primary_key]

      case relation.macro
      when :belongs_to
        # Связь в этой таблице - получить нужные id = вытянуть значения
        (relation_primary_key || relation.klass.primary_key).to_s
      when :has_many, :has_one
        # Связь с другой таблице - получить где relation_foreign_key = текущие значения
        relation_foreign_key
      when :has_and_belongs_to_many
        'id'
      else
        print "Unknown macro in relation #{relation.macro}", iteration
      end
    end

    def validate_model_by_name(model_name, iteration)
      model_name.constantize.primary_key.to_s
      true
    rescue NameError, LoadError, NoMethodError => e # rubocop:disable Lint/ShadowedException
      print "CRITICAL WARNING!!! #{e}", iteration
      false
    end

    def log_model_warnings(current_model)
      current_model.warnings.each do |warning|
        print "CRITICAL WARNING!!! #{warning}", current_model.iteration
      end
    end

    def valid_relation?(relation, current_model)
      # у полиморфных связей relation.klass не иницализирован (OperationLog::Source не существует)
      return true if relation.options[:polymorphic]

      begin
        relation.klass.connection
        relation.klass.primary_key
        true
      rescue NameError, LoadError => e
        print "CRITICAL WARNING!!! #{e}", current_model.iteration
        false
      end
    end

    def relation_already_exist?(model, dump_state)
      buffer = "Relation #{model.to_short_str} already exists?"
      if dump_state.include_relation?(model)
        print "#{buffer} Yes", model.iteration if full_debug_mode?
        return true
      end

      print "#{buffer}  No", model.iteration if full_debug_mode?
      false
    end

    def excluded?(current_model, relation)
      relation_name = "#{current_model.source_model}.#{relation.name}"
      if FuryDumper::Config.exclude_relation?(relation_name)
        print "Exclude relation: #{relation_name}", current_model.iteration
        return true
      end

      false
    end

    def through?(relation, iteration)
      if relation.options[:through]
        print "Ignore through relation #{relation.name}", iteration
        return true
      end

      false
    end

    def empty_active_record?(current_model, buffer)
      unless current_model.to_active_record_relation.exists?
        print "#{buffer} (empty active record)", current_model.iteration
        return true
      end

      false
    end

    def other_db?(relation, iteration)
      # Check this db
      if relation.klass.connection.current_database != target_database
        print "Ignore #{relation.klass} from other db #{relation.klass.connection.current_database}", iteration
        return true
      end

      false
    end

    def narrowing_relation?(relation, current_model)
      relation_class = relation.klass.to_s

      if current_model.all_non_scoped_models.include?(relation_class)
        if full_debug_mode?
          print "Narrowing relation #{current_model.source_model}(#{relation.name})",
                current_model.iteration
        end
        return true
      end

      false
    end

    def print_new_model(current_model, relation)
      r_class       = relation.klass.to_s
      s_field_name  = self_field_name(current_model, relation)
      r_field_name  = relation_field_name(relation, current_model.iteration)

      print "#{current_model.source_model}[#{relation.macro}] -> #{r_class} (#{s_field_name} -> #{r_field_name})",
            current_model.iteration
    end

    def debug_mode?
      @debug_mode != :none
    end

    def full_debug_mode?
      @debug_mode == :full
    end

    def print(message, indent)
      p "[#{Time.now.httpdate}]#{format('%03d', indent)} #{'-' * indent}> #{message}" if debug_mode?
    end

    def target_database
      ActiveRecord::Base.connection_config[:database]
    end

    def attribute_values(active_record_values, field_name)
      active_record_values.map { |rel| rel.read_attribute(field_name) }.uniq
    end

    def fetch_scope_items(current_model, relation)
      return [] unless relation.scope

      # Exclude some like this has_one :citizenship, ->(d) { where(lead_id: d.lead_id) }
      return [] if relation.scope.lambda?

      return [] if narrowing_relation?(relation, current_model)

      if full_debug_mode?
        print "Scoped relation will dump #{current_model.source_model}(#{relation.name})",
              current_model.iteration
      end

      scope_queue = relation.klass.instance_exec(&relation.scope)
      connection  = relation.klass.connection
      visitor     = connection.visitor

      binds       = bind_values(scope_queue, connection)

      where_values(scope_queue).map do |arel|
        if arel.is_a?(String)
          RelationItem.new(key: arel, values_for_key: nil, complex: true)
        elsif arel.is_a?(Arel::Nodes::Node)
          arel_node_parse(arel, connection, visitor, binds)
        end
      end
    end

    def bind_values(scope_queue, connection)
      if ActiveRecord.version.version.to_f < 5.0
        binds = scope_queue.bind_values.dup
        binds.map! { |bv| connection.quote(*bv.reverse) }
      elsif ActiveRecord.version.version.to_d == 5.0.to_d
        binds = scope_queue.bound_attributes.map(&:value).dup
        binds.map! { |bv| connection.quote(*bv) }
      else
        []
      end
    end

    def arel_node_parse(arel, connection, visitor, binds = [])
      result = if ActiveRecord.version.version.to_f < 5.0
                 collect  = visitor.accept(arel, Arel::Collectors::Bind.new)
                 result   = collect.substitute_binds(binds).join
                 binds.delete_at(0)
                 result
               elsif ActiveRecord.version.version.to_d == 5.0.to_d
                 collector  = ActiveRecord::ConnectionAdapters::AbstractAdapter::BindCollector.new
                 collect    = visitor.accept(arel, collector)
                 result     = collect.substitute_binds(binds).join
                 binds.delete_at(0)
                 result
               else
                 collector = Arel::Collectors::SubstituteBinds.new(
                   connection,
                   Arel::Collectors::SQLString.new
                 )
                 visitor.accept(arel, collector).value
               end

      Dumpers::RelationItem.new(key: result, values_for_key: nil, complex: true)
    end

    def where_values(scope_queue)
      if ActiveRecord.version.version.to_f < 5.0
        scope_queue.where_values
      else
        scope_queue.where_clause.send(:predicates)
      end
    end

    def default_psql_keys
      "-d #{@database} -h #{@host} -p #{@port} -U #{@user}"
    end

    def cur_connection
      @cur_connection = ActiveRecord::Base.establish_connection(save_current_config)
      @cur_connection.connection
    end

    def dump_by_sql(select_sql, table_name, table_primary_key, current_connection)
      system "export PGPASSWORD=#{@password} && psql #{default_psql_keys} -c \"\\COPY (#{select_sql}) TO " \
             "'/tmp/tmp_copy.copy' WITH (FORMAT CSV, FORCE_QUOTE *);\" >> '/dev/null'"

      tmp_table_name = "tmp_#{table_name}"
      # copy to tmp table
      current_connection.execute "CREATE TEMP TABLE #{tmp_table_name} (LIKE #{table_name} EXCLUDING ALL);"
      current_connection.execute "COPY #{tmp_table_name} FROM '/tmp/tmp_copy.copy' WITH (FORMAT CSV);"

      # delete existing records
      current_connection.execute "ALTER TABLE #{table_name} DISABLE TRIGGER ALL;"
      current_connection.execute "DELETE FROM #{table_name} WHERE #{table_name}.#{table_primary_key} IN " \
                                 "(SELECT #{table_primary_key} FROM #{tmp_table_name});"

      # copy to target table
      current_connection.execute "COPY #{table_name} FROM '/tmp/tmp_copy.copy' WITH (FORMAT CSV);"
      current_connection.execute "ALTER TABLE #{table_name} ENABLE TRIGGER ALL;"

      current_connection.execute "DROP TABLE #{tmp_table_name};"
    end

    def dump_model(model)
      current_connection = cur_connection
      current_connection.transaction do
        select_sql = model.to_active_record_relation.to_sql

        dump_by_sql(select_sql, model.table_name, model.primary_key, current_connection)
      rescue ActiveRecord::ActiveRecordError => e
        @undump_models << { model: model, error: e }
        print "CRITICAL WARNING!!! #{e}", model.iteration
      end
      true
    end

    # @return [Array of String] association foreign values
    def dump_proxy_table(model, relation)
      current_connection = cur_connection
      current_connection.transaction do
        select_sql        = model.to_active_record_relation.select(model.primary_key).to_sql
        proxy_table       = relation.options[:join_table].to_s
        proxy_foreign_key = relation.options[:foreign_key] || relation.foreign_key

        proxy_select      = "SELECT * FROM #{proxy_table} WHERE #{proxy_foreign_key} IN (#{select_sql})"
        dump_by_sql(proxy_select, proxy_table, 'id', current_connection)

        # Get association foreign values
        association_foreign_key = relation.options[:association_foreign_key].to_s
        cur_connection.exec_query(proxy_select).to_a.pluck(association_foreign_key).uniq
      rescue ActiveRecord::ActiveRecordError => e
        @undump_models << { model: model, error: e }
        print "CRITICAL WARNING!!! #{e}", model.iteration
        []
      end
    end

    def print_undump_models
      p '⚠️ ⚠️ ⚠️ These models were not dump due to pg errors ️⚠️ ⚠️ ⚠️' if @undump_models.present?
      @undump_models.each do |model|
        p "🔥 #{model[:model].to_full_str}"
        p "🔥 #{model[:error]}"
      end
    end

    def humanize_hash(hash)
      hash.map do |k, v|
        "#{k}: #{v}"
      end.join(', ')
    end

    def difference(this_val, other_val)
      (this_val - other_val) | (other_val - this_val)
    end

    def save_current_config
      @save_current_config ||= ActiveRecord::Base.connection_config
    end

    def remote_connection
      save_current_config
      @remote_connection = ActiveRecord::Base.establish_connection(adapter: 'postgresql',
                                                                   database: @database,
                                                                   host: @host,
                                                                   port: @port,
                                                                   username: @user,
                                                                   password: @password)
      @remote_connection.connection
    end

    def send_out_ms_dump(model)
      return unless FuryDumper::Config.ms_relations?(model.table_name)

      FuryDumper::Config.relative_services.each do |ms_name, ms_config|
        ms_config['tables'][model.table_name]&.each do |_other_model, other_model_config|
          self_field_name = other_model_config['self_field_name']
          as_field_name   = "#buff_#{self_field_name.gsub(/\W+/, '')}"

          selected_values = attribute_values(
            model.to_active_record_relation.select("#{self_field_name} AS #{as_field_name}"), as_field_name
          )

          next if selected_values.to_a.compact.blank?

          Api.new(ms_name).send_request(other_model_config['ms_model_name'],
                                        other_model_config['ms_field_name'],
                                        selected_values.to_a)
        end
      end
    end
  end
end
