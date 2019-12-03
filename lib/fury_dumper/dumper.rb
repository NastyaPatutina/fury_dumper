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
      @dump_state =     DumpState.new(root_source_model: @model_name)
      @undump_models =  []
    end

    def sync_models
      p "--- Dump models ---"
      if FuryDumper::Config.mode == :wide
        sync_model_in_wight(@model)
      else
        sync_model_in_depth(@model)
      end

      @dump_state.stop
      print_undump_models
    end

    def have_equal_schemas?
      tables_list   = cur_connection.tables.map { |e| "'" + e + "'" }.join(', ')
      sql           = "SELECT column_name, data_type, table_name FROM INFORMATION_SCHEMA.COLUMNS WHERE table_name IN (#{tables_list});"
      cur_schema    = cur_connection.exec_query(sql).to_a
      remote_schema = remote_connection.exec_query(sql).to_a
      difference    = difference(remote_schema, cur_schema)

      if difference.present?
        difference.group_by { |e| e["table_name"] }.each do |table_name, diff|
          p "💣 Found difference for table #{table_name}"
          diff.sort_by { |e| e["column_name"] }.each do |dif|
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

      return if is_empty_active_record?(model, buffer)

      print buffer, model.iteration

      active_record_model.reflect_on_all_associations.each do |relation|
        # Проверка на корректную связь
        next unless valid_relation?(relation, model)

        # Исключения
        next if is_excluded?(model, relation)

        # Игнорим through
        next if is_through?(relation, model.iteration)

        # Если связана с полиморфной сущностью ...
        new_models = build_polymorphic_models(model, relation)
        unless new_models.nil?
          new_models.each do |new_model|
            sync_model_in_depth(new_model)
          end

          next
        end

        # Игнорим связи для другой БД
        next if is_other_db?(relation, model.iteration)

        print_new_model(model, relation)

        new_model = build_as_models(model, relation, @dump_state) ||
            build_default_model(model, relation, @dump_state)

        next if new_model.nil?

        sync_model_in_depth(new_model)
      end

      log_model_warnings(model)
      true
    end

    def sync_model_in_wight(model, model_queue = ModelQueue.new)
      print "Start #{model.to_short_str} dump", model.iteration if full_debug_mode?
      model_queue.add_element(model: model, dump_state: @dump_state)

      until model_queue.empty?
        current_model, dump_state = model_queue.get_element
        print "Relation #{current_model.to_short_str} start dump (queue size - #{model_queue.count})",
              current_model.iteration if full_debug_mode?

        active_record_model = current_model.active_record_model
        next if relation_already_exist?(current_model, dump_state)

        # Добавляем в список моделей, которые уже стащили
        dump_state.add_loaded_relation(current_model)

        buffer = current_model.to_full_str
        next unless dump_model(current_model)
        send_out_ms_dump(current_model)

        next if is_empty_active_record?(current_model, buffer)
        print buffer, current_model.iteration

        active_record_model.reflect_on_all_associations.each do |relation|
          # Проверка на корректную связь
          next unless valid_relation?(relation, current_model)

          # Исключения
          next if is_excluded?(current_model, relation)

          # Игнорим through
          next if is_through?(relation, current_model.iteration)

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
          next if is_other_db?(relation, current_model.iteration)

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

      new_model = Model.new(source_model: relation_class,
                            relation_items: RelationItems.new_with_key_value(item_key: relation_field_name,
                                                                             item_values: []),
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

      items = [RelationItem.new(key: relation_field_name, values: relation_values)]

      # Если связь со scope, получить все условия
      items += get_scope_items(current_model, relation)

      new_model.relation_items = RelationItems.new_with_items(items: items)

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

      print "Found polymorphic relation #{current_model.source_model}(#{relation.name.to_s}): #{ polymorphic_models.join(', ') }",
            current_model.iteration

      polymorphic_models.map do |polymorphic_model|
        next unless polymorphic_model
        next unless validate_model_by_name(polymorphic_model, current_model.iteration)

        polymorphic_primary_key = polymorphic_model.constantize.primary_key.to_s
        type_values             = Hash[relation.foreign_type, polymorphic_model]
        polymorphic_values      = attribute_values(active_record_values.where(type_values), relation_foreign_key)

        Model.new(source_model: polymorphic_model,
                  relation_items: RelationItems.new_with_key_value(item_key: polymorphic_primary_key,
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

      new_model = Model.new(source_model: relation_class,
                            relation_items: RelationItems.new_with_key_value(item_key: relation_field_name,
                                                                             item_values: []),
                            iteration: current_model.next_iteration,
                            root_model: current_model.root_model)

      print "Add source for #{current_model.source_model}(#{relation.name.to_s})", current_model.iteration

      active_record_values  = current_model.to_active_record_relation
      relation_field_values = attribute_values(active_record_values, self_field_name)

      items = [RelationItem.new(key: relation_field_name, values: relation_field_values),
               RelationItem.new(key: relation.type, values: [current_model.source_model], additional: true)]

      new_model.relation_items  = RelationItems.new_with_items(items: items)
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
        return relation_foreign_key
      when :has_many, :has_one
        # Связь с другой таблице - получить где relation_foreign_key = текущие значения
        return (relation_primary_key || current_model.primary_key).to_s
      when :has_and_belongs_to_many
        return 'id'
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
        return (relation_primary_key || relation.klass.primary_key).to_s
      when :has_many, :has_one
        # Связь с другой таблице - получить где relation_foreign_key = текущие значения
        return relation_foreign_key
      when :has_and_belongs_to_many
        return 'id'
      else
        print "Unknown macro in relation #{relation.macro}", iteration
      end
    end

    def validate_model_by_name(model_name, iteration)
      begin
        model_name.constantize.primary_key.to_s
        true
      rescue NameError, LoadError, NoMethodError => error
        print "CRITICAL WARNING!!! #{error}", iteration
        false
      end
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
      rescue NameError, LoadError => error
        print "CRITICAL WARNING!!! #{error}", current_model.iteration
        false
      end
    end

    def relation_already_exist?(model, dump_state)
      buffer = "Relation #{model.to_short_str} already exists?"
      if dump_state.include_relation?(model)
        print buffer + " Yes", model.iteration if full_debug_mode?
        return true
      end

      print buffer + " No", model.iteration if full_debug_mode?
      false
    end

    def is_excluded?(current_model, relation)
      relation_name = "#{current_model.source_model}.#{relation.name}"
      if FuryDumper::Config.is_exclude_relation?(relation_name)
        print "Exclude relation: #{relation_name}", current_model.iteration
        return true
      end

      false
    end

    def is_through?(relation, iteration)
      if relation.options[:through]
        print "Ignore through relation #{relation.name.to_s}", iteration
        return true
      end

      false
    end

    def is_empty_active_record?(current_model, buffer)
      unless current_model.to_active_record_relation.exists?
        print buffer + "(empty active record)", current_model.iteration
        return true
      end

      false
    end

    def is_other_db?(relation, iteration)
      # Check this db
      if relation.klass.connection.current_database != target_database
        print "Ignore #{relation.klass} from other db #{relation.klass.connection.current_database}", iteration
        return true
      end

      false
    end

    def is_narrowing_relation?(relation, current_model)
      relation_class = relation.klass.to_s

      if current_model.all_non_scoped_models.include?(relation_class)
        print "Narrowing relation #{current_model.source_model}(#{relation.name.to_s})",
              current_model.iteration if full_debug_mode?
        return true
      end

      false
    end

    def print_new_model(current_model, relation)
      r_class       = relation.klass.to_s
      s_field_name  = self_field_name(current_model, relation)
      r_field_name  = relation_field_name(relation, current_model.iteration)

      print "#{current_model.source_model}[#{relation.macro.to_s}] -> #{r_class} (#{s_field_name} -> #{r_field_name})",
            current_model.iteration
    end

    def debug_mode?
      @debug_mode != :none
    end

    def full_debug_mode?
      @debug_mode == :full
    end

    def print(message, indent)
      p "[#{Time.now.to_s(:db)}]#{ format('%03d', indent)} #{'-' * indent}> #{message}" if debug_mode?
    end

    def target_database
      ActiveRecord::Base.connection_config[:database]
    end

    def attribute_values(active_record_values, field_name)
      active_record_values.map { |rel| rel.read_attribute(field_name) }.uniq
    end

    def get_scope_items(current_model, relation)
      return [] unless relation.scope

      # Exclude some like this has_one :citizenship, ->(d) { where(lead_id: d.lead_id) }
      return [] if relation.scope.lambda?

      return [] if is_narrowing_relation?(relation, current_model)

      print "Scoped relation will dump #{current_model.source_model}(#{relation.name.to_s})",
            current_model.iteration if full_debug_mode?

      scope_queue = relation.klass.instance_exec(&relation.scope)
      connection  = relation.klass.connection
      visitor     = connection.visitor

      binds       = bind_values(scope_queue, connection)

      where_values(scope_queue).map do |arel|
        if arel.is_a?(String)
          RelationItem.new(key: arel, values: nil, complex: true)
        elsif arel.is_a?(Arel::Nodes::Node)
          arel_node_parse(arel, connection, visitor, binds)
        end
      end
    end

    def bind_values(scope_queue, connection)
      if ActiveRecord.version.version.to_f < 5.0
        binds = scope_queue.bind_values.dup
        binds.map! { |bv| connection.quote(*bv.reverse) }
      elsif ActiveRecord.version.version.to_f == 5.0
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
               elsif ActiveRecord.version.version.to_f == 5.0
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

      RelationItem.new(key: result, values: nil, complex: true)
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
      cur_config = save_current_config
      @connection ||= if cur_config != ActiveRecord::Base.connection_config
                        ActiveRecord::Base.establish_connection(cur_config).connection
                      else
                        ActiveRecord::Base.connection
                      end
    end

    def dump_by_sql(select_sql, table_name, table_primary_key)
      system "export PGPASSWORD=#{@password} && psql #{default_psql_keys} -c \"\\COPY (#{select_sql}) TO '/tmp/tmp_copy.copy' WITH (FORMAT CSV, FORCE_QUOTE *);\" >> '/dev/null'"

      tmp_table_name = "tmp_#{table_name}"
      # copy to tmp table
      cur_connection.execute "CREATE TEMP TABLE #{tmp_table_name} (LIKE #{table_name} EXCLUDING ALL);"
      cur_connection.execute "COPY #{tmp_table_name} FROM '/tmp/tmp_copy.copy' WITH (FORMAT CSV);"

      # delete existing records
      cur_connection.execute "ALTER TABLE #{table_name} DISABLE TRIGGER ALL;"
      cur_connection.execute "DELETE FROM #{table_name} WHERE #{table_name}.#{table_primary_key} IN (SELECT #{table_primary_key} FROM #{tmp_table_name});"

      # copy to target table
      cur_connection.execute "COPY #{table_name} FROM '/tmp/tmp_copy.copy' WITH (FORMAT CSV);"
      cur_connection.execute "ALTER TABLE #{table_name} ENABLE TRIGGER ALL;"

      cur_connection.execute "DROP TABLE #{tmp_table_name};"
    end

    def dump_model(model)
      ActiveRecord::Base.transaction do
        select_sql = model.to_active_record_relation.to_sql

        dump_by_sql(select_sql, model.table_name, model.primary_key)
      rescue ActiveRecord::ActiveRecordError => error
        @undump_models << {model: model, error: error}
        print "CRITICAL WARNING!!! #{error}", model.iteration
        return true
      end
      true
    end

    # @return [Array of String] association foreign values
    def dump_proxy_table(model, relation)
      ActiveRecord::Base.transaction do
        select_sql        = model.to_active_record_relation.select(model.primary_key).to_sql
        proxy_table       = relation.options[:join_table].to_s
        proxy_foreign_key = relation.options[:foreign_key] || relation.foreign_key

        proxy_select      = "SELECT * FROM #{proxy_table} WHERE #{proxy_foreign_key} IN (#{select_sql})"
        dump_by_sql(proxy_select, proxy_table, 'id')

        # Get association foreign values
        association_foreign_key = relation.options[:association_foreign_key].to_s
        cur_connection.exec_query(proxy_select).to_a.map { |ss| ss[association_foreign_key] }.uniq
      rescue ActiveRecord::ActiveRecordError => error
        @undump_models << {model: model, error: error}
        print "CRITICAL WARNING!!! #{error}", model.iteration
        []
      end
    end

    def print_undump_models
      p "⚠️ ⚠️ ⚠️ These models were not dump due to pg errors ️⚠️ ⚠️ ⚠️" if @undump_models.present?
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

    def difference(a, b)
      a - b | b - a
    end

    def save_current_config
      @cur_config ||= ActiveRecord::Base.connection_config
    end

    def remote_connection
      save_current_config
      @remote_connection ||= ActiveRecord::Base.establish_connection(adapter: 'postgresql',
                                                                     database: @database,
                                                                     host: @host,
                                                                     port: @port,
                                                                     username: @user,
                                                                     password: @password).connection
    end

    def send_out_ms_dump(model)
      return unless FuryDumper::Config.has_ms_relations?(model.table_name)
      FuryDumper::Config.relative_services.each do |ms_name, ms_config|
        ms_config['tables'][model.table_name]&.each do |other_model, other_model_config|
          self_field_name = other_model_config['self_field_name']
          as_field_name   = "buff_" + self_field_name.gsub(/\W+/, '')

          selected_values = attribute_values(model.to_active_record_relation.select("#{self_field_name} AS #{as_field_name}"), as_field_name)

          next if selected_values.to_a.compact.blank?
          Api.new(ms_name).send_request(other_model_config['ms_model_name'],
                                        other_model_config['ms_field_name'],
                                        selected_values.to_a)
        end
      end
    end
  end
end
