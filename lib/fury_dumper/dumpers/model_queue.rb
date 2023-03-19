# frozen_string_literal: true

module FuryDumper
  module Dumpers
    class ModelQueue
      def initialize
        @queue = []
      end

      def add_element(model:, dump_state:)
        raise ArgumentError, "Expected model as Dumpers::Model, got: #{model.class}" unless model.is_a?(Model)

        unless dump_state.is_a?(DumpState)
          raise ArgumentError,
                "Expected dump_state as Dumpers::DumpState, got: #{dump_state.class}"
        end

        @queue << [model, dump_state]
      end

      def empty?
        @queue.empty?
      end

      def fetch_element
        @queue.delete_at(0)
      end

      def count
        @queue.count
      end
    end
  end
end
