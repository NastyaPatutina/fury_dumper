module FuryDumper
  class Dumper::DumpState
    attr_accessor :batch, :root_source_model, :loaded_relations, :iteration

    def initialize(root_source_model:, loaded_relations: [])
      @root_source_model  = root_source_model
      @loaded_relations   = loaded_relations
      @start_time         = Time.now
    end

    def stop
      @end_time = Time.now
    end

    def include_relation?(relation_name)
      loaded_relations.include?(relation_name)
    end

    def add_loaded_relation(new_relation)
      raise ArgumentError unless new_relation.is_a?(Dumper::Model)

      loaded_relations << new_relation unless include_relation?(new_relation)
    end

    def print_statistic
      p "📈 Statistic for #{@root_source_model.to_s} dump"
      p "Execution time: #{duration}"
      p "Loaded #{@loaded_relations.count} relations"
      p "Loaded #{@loaded_relations.map(&:source_model).uniq.count} uniq models"

      p "Most repeatable models relations:"
      @loaded_relations.group_by { |relation| relation.source_model }.sort_by { |k, v| v.count }.last(10).each { |k, v| p "  #{k}: #{v.count} times" }
    end

    private
    def duration
      secs  = (@end_time - @start_time).to_int
      mins  = secs / 60
      hours = mins / 60
      days  = hours / 24

      if days > 0
        "#{days} days and #{hours % 24} hours"
      elsif hours > 0
        "#{hours} hours and #{mins % 60} minutes"
      elsif mins > 0
        "#{mins} minutes and #{secs % 60} seconds"
      elsif secs >= 0
        "#{secs} seconds"
      end
    end
  end
end
