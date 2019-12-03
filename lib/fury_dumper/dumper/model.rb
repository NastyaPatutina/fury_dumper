module FuryDumper
  class Dumper::Model
    attr_reader :source_model, :iteration, :root_model, :warnings
    attr_accessor :relation_items, :root_model

    def initialize(source_model:, relation_items:, iteration: 0, root_model: nil)
      raise ArgumentError unless source_model.is_a?(String)
      raise ArgumentError unless relation_items.is_a?(Dumper::RelationItems)
      raise ArgumentError unless iteration.is_a?(Numeric)
      raise ArgumentError unless root_model.is_a?(Dumper::Model) || root_model.nil?

      @source_model   = source_model
      @relation_items = relation_items
      @iteration      = iteration
      @root_model     = root_model
      @warnings       = []
    end

    def copy
      self.class.new(source_model:    source_model,
                     relation_items:  relation_items.copy,
                     iteration:       iteration,
                     root_model:      root_model)
    end

    def table_name
      active_record_model.table_name
    end

    def column_names
      active_record_model.columns.map(&:name)
    end

    def ==(other)
      raise ArgumentError unless other.is_a?(Dumper::Model)

      @source_model == other.source_model &&
          @relation_items.eql?(other.relation_items) &&
          is_sub_path?(other)
    end

    def is_sub_path?(other_model)
      raise ArgumentError unless other_model.is_a?(Dumper::Model)

      min_length = [root_path.length, other_model.root_path.length].min - 1
      root_path[0..min_length] == other_model.root_path[0..min_length]
    end

    def root_path
      return [nil] if @root_model.nil?

      @root_model.root_path + [@root_model.source_model]
    end

    def to_full_str
      buffer = "MODEL "
      buffer << @source_model.to_s
      buffer << " by #{root_model&.source_model.presence || '-'} "

      buffer << "WHERE "
      buffer << @relation_items.items.map do |item|
        if item.complex
          item.key
        elsif item.values.count > 10
          "#{item.key} = #{item.values[0..10]} and #{item.values.count - 10} elements"
        else
          "#{item.key} = #{item.values}"
        end
      end.join(' AND ')

      buffer
    end

    def active_record_model
      @source_model.constantize
    end

    def primary_key
      active_record_model.primary_key
    end

    def to_short_str
      "#{@source_model}.#{@relation_items.keys.join(' & ')}"
    end

    def get_complex_items
      @relation_items.complex_items.map(&:key).join(' AND ')
    end

    def get_equality_items_hash
      values = {}
      @relation_items.equality_items.each do |item|
        if active_record_model.column_names.include?(item.key)
          values[item.key] = item.values
        else
          @warnings << "Shit relation: #{@source_model}.#{item.key} does not exist"
          next
        end
      end

      values
    end

    def all_non_scoped_models
      active_record_model.reflect_on_all_associations.select { |rr| rr.scope.nil? }.map do |rr|
        begin
          rr.klass.to_s
        rescue NameError, LoadError => error
          @warnings << error
          next
        end
      end.compact.uniq
    end

    def to_active_record_relation
      return @active_record_relation if @active_record_relation

      complex_values          = get_complex_items
      equality_values         = get_equality_items_hash
      @active_record_relation = active_record_model.where(equality_values).
                                                    where(complex_values).
                                                    limit(FuryDumper::Config.limit)

      unless FuryDumper::Config.is_fast
        order_value = Hash[primary_key, :desc]
        @active_record_relation = @active_record_relation.order(order_value)
      end

      @active_record_relation
    end

    def next_iteration
      @iteration + 1
    end
  end
end
