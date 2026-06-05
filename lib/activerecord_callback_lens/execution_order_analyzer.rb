# frozen_string_literal: true

module ActiverecordCallbackLens
  # Sorts a list of Collector::CallbackDefinition objects into the canonical
  # order in which Rails executes callbacks on a record save.
  #
  # Two orderings are supported, selected via the +operation+ keyword:
  #
  # * +:create+ (the default) follows the create path
  #   (before_create / after_create around the INSERT).
  # * +:update+ follows the update path
  #   (before_update / after_update around the UPDATE).
  #
  # A definition's position is derived from its +phase_event+ pair (for example
  # +before_save+). Callbacks whose pair is not part of the canonical order are
  # placed at the end (sort index 999) while preserving their relative order,
  # because Ruby's Array#sort_by is stable for equal keys.
  class ExecutionOrderAnalyzer
    # Canonical create-path order. Mirrors spec section 7.1 (create path).
    SAVE_ORDER = %i[
      before_validation after_validation
      before_save
      before_create
      after_create
      after_save
      after_commit
    ].freeze

    # Canonical update-path order. Mirrors spec section 7.1 (update path).
    UPDATE_ORDER = %i[
      before_validation after_validation
      before_save
      before_update
      after_update
      after_save
      after_commit
    ].freeze

    # Sort index assigned to callbacks whose phase_event pair is not part of the
    # canonical order, so they sort after every recognised callback.
    UNRECOGNISED_INDEX = 999

    # Sorts +definitions+ into canonical execution order.
    #
    # @param definitions [Array<Collector::CallbackDefinition>]
    # @param operation [Symbol] :create (default) or :update
    # @return [Array<Collector::CallbackDefinition>] a new sorted array
    def self.sort(definitions, operation: :create)
      order = operation == :update ? UPDATE_ORDER : SAVE_ORDER
      definitions.sort_by do |definition|
        key = :"#{definition.phase}_#{definition.event}"
        order.index(key) || UNRECOGNISED_INDEX
      end
    end
  end
end
