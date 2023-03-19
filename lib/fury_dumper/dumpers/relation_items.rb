# frozen_string_literal: true

module FuryDumper
  module Dumpers
    RelationItem = Struct.new(:key, :values_for_key, :complex, :additional) do
      def initialize(key:, values_for_key:, complex: false, additional: false)
        super(key, values_for_key, complex, additional)
      end

      def eql?(other)
        key == other.key
      end

      def copy
        self.class.new(key: key, values_for_key: values_for_key.dup, complex: complex, additional: additional)
      end
    end

    class RelationItems
      attr_accessor :items

      def initialize(items: [])
        raise ArgumentError unless items.is_a?(Array)
        raise ArgumentError unless items.all? { |item| item.is_a?(RelationItem) }

        @items = items
      end

      def self.new_with_key_value(item_key: 'id', item_values: [])
        new(items: [RelationItem.new(key: item_key, values_for_key: item_values.compact)])
      end

      def self.new_with_items(items: [])
        new(items: items)
      end

      def eql?(other)
        raise ArgumentError unless other.is_a?(RelationItems)

        other.items.reject(&:additional).all? do |other_item|
          items.reject(&:additional).any? { |item| item.eql?(other_item) }
        end
      end

      def equality_items
        items.reject(&:complex)
      end

      def complex_items
        items.select(&:complex)
      end

      def keys
        items.map(&:key).sort
      end

      def values(key)
        items.select { |item| item.key == key }.values_for_key
      end

      def copy
        self.class.new(items: copy_items)
      end

      def copy_items
        items.map(&:copy)
      end

      def copy_with_new_values(key, new_values)
        new_items = copy_items
        new_items.each do |item|
          item.values_for_key = new_values.compact.dup if item.key == key
        end

        self.class.new_with_items(items: new_items)
      end
    end
  end
end
