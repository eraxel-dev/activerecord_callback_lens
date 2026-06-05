# frozen_string_literal: true

require_relative "callback_definition"

module ActiverecordCallbackLens
  module Collector
    # Reads ActiveRecord's internal callback chains for a model class and returns
    # an array of CallbackDefinition structs with raw condition data, ready for
    # the Parser layer to populate +condition_tree+.
    #
    # Each of the five callback events (save, create, update, destroy, validation)
    # is accessed through ActiveRecord's private chain accessor and every
    # ActiveSupport::Callbacks::Callback in the chain is converted into one
    # CallbackDefinition.
    class CallbackCollector
      # The callback events enumerated, in a stable order.
      EVENTS = %i[save create update destroy validation].freeze

      # Maps each event to ActiveRecord's internal callback chain accessor.
      CHAIN_METHODS = {
        save: :_save_callbacks,
        create: :_create_callbacks,
        update: :_update_callbacks,
        destroy: :_destroy_callbacks,
        validation: :_validation_callbacks
      }.freeze

      # Collect all callbacks registered on a model class.
      #
      # @param model_class [Class] an ActiveRecord::Base subclass
      # @return [Array<CallbackDefinition>]
      def self.collect(model_class)
        new(model_class).collect
      end

      # @param model_class [Class] an ActiveRecord::Base subclass
      def initialize(model_class)
        @model_class = model_class
      end

      # @return [Array<CallbackDefinition>]
      def collect
        EVENTS.flat_map { |event| collect_event(event) }
      end

      private

      # @param event [Symbol]
      # @return [Array<CallbackDefinition>]
      def collect_event(event)
        chain = @model_class.send(CHAIN_METHODS[event])
        chain.map { |callback| build_definition(callback, event) }
      end

      # @param callback [ActiveSupport::Callbacks::Callback]
      # @param event [Symbol]
      # @return [CallbackDefinition]
      def build_definition(callback, event)
        filter = callback.filter
        CallbackDefinition.new(
          model: @model_class,
          event: event,
          phase: callback.kind,
          filter: filter,
          raw_conditions: extract_conditions(callback),
          condition_tree: nil,
          source_location: resolve_location(filter)
        )
      end

      # Extracts the raw if/unless condition arrays from a callback's internals.
      #
      # @param callback [ActiveSupport::Callbacks::Callback]
      # @return [Hash{Symbol => Array}]
      def extract_conditions(callback)
        {
          if: Array(callback.instance_variable_get(:@if)),
          unless: Array(callback.instance_variable_get(:@unless))
        }
      end

      # Resolves the source location for a filter when possible.
      #
      # Proc/Lambda filters expose +source_location+; Symbol filters are resolved
      # later by the MethodResolver (v0.2), and String filters have no location.
      #
      # @param filter [Symbol, Proc, String]
      # @return [Array(String, Integer), nil]
      def resolve_location(filter)
        case filter
        when Proc then filter.source_location
        end
      end
    end
  end
end
