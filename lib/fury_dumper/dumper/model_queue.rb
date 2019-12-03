module FuryDumper
  class Dumper::ModelQueue
    def initialize
      @queue = []
    end

    def add_element(model:, dump_state:)
      raise ArgumentError, "Expected model as Dumper::Model, got: #{model.class}" unless model.is_a?(Dumper::Model)
      raise ArgumentError, "Expected dump_state as Dumper::DumpState, got: #{dump_state.class}" unless dump_state.is_a?(Dumper::DumpState)

      @queue << [model, dump_state]
    end

    def empty?
      @queue.empty?
    end

    def get_element
      @queue.delete_at(0)
    end

    def count
      @queue.count
    end
  end
end
