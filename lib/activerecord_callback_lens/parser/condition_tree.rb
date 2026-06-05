# frozen_string_literal: true

module ActiverecordCallbackLens
  module Parser
    # The ConditionTree is the parsed, logical representation of a callback's
    # if/unless conditions. Every node is an immutable Data type.
    module ConditionTree
      # Base node carrying an arbitrary set of children. Retained for
      # forward-compatibility with generic tree traversals.
      Node = Data.define(:children)

      # Logical combinators.
      AndNode = Data.define(:children) # children: Array<Node>
      OrNode  = Data.define(:children) # children: Array<Node>
      NotNode = Data.define(:child)    # child: Node

      # Leaf: a single predicate method call, e.g. "saved_change_to_title?".
      PredicateNode = Data.define(:name) # name: String

      # Leaf: a symbol condition such as :sync_required?.
      # expanded_tree is the result of MethodResolver, nil in v0.1 / when unresolved.
      MethodRefNode = Data.define(:name, :expanded_tree) # name: String, expanded_tree: Node | nil
    end
  end
end
