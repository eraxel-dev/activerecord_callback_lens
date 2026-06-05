# frozen_string_literal: true

module ActiverecordCallbackLens
  module Collector
    # Represents a single callback registered on an ActiveRecord model.
    #
    # event + phase together reconstruct the full callback name
    # (e.g. :before + :save => before_save).
    # raw_conditions holds the unprocessed if/unless arrays from AR internals.
    # condition_tree is nil until the Parser populates it (nil when no conditions).
    CallbackDefinition = Data.define(
      :model,           # Class — the ActiveRecord model class
      :event,           # Symbol — :save, :create, :update, :destroy, :validation
      :phase,           # Symbol — :before, :after, :around
      :filter,          # Symbol | Proc | String — the callback body
      :raw_conditions,  # { if: [...], unless: [...] } — raw arrays from AR internals
      :condition_tree,  # ConditionTree::Node | nil — parsed logical tree
      :source_location  # [String, Integer] | nil — file and line of the filter
    )
  end
end
