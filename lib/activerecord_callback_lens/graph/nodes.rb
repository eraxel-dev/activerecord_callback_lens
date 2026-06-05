# frozen_string_literal: true

module ActiverecordCallbackLens
  module Graph
    # The graph layer turns a list of CallbackDefinition objects (with their
    # parsed ConditionTrees) into a directed acyclic graph of typed nodes and
    # labelled edges, ready for a renderer to emit.
    #
    # Every node carries a unique +id+ (assigned by the GraphBuilder) plus the
    # domain object it represents. Edges connect a child node to its parent via
    # +from_id+ / +to_id+ and carry a +label+ describing the relationship
    # (+:requires+ for condition/predicate/method dependencies).
    #
    # All node and edge types are immutable Data values.

    # One node per CallbackDefinition, e.g. before_save / after_commit.
    # definition: Collector::CallbackDefinition
    CallbackNode = Data.define(:id, :definition)

    # One node per logical combinator (AndNode / OrNode) in a ConditionTree.
    # tree_node: ConditionTree::AndNode | ConditionTree::OrNode
    ConditionNode = Data.define(:id, :tree_node)

    # One node per Symbol condition (e.g. :sync_required?). method_name: String
    MethodNode = Data.define(:id, :method_name)

    # One node per predicate method call (e.g. saved_change_to_title?).
    # predicate_name: String
    PredicateNode = Data.define(:id, :predicate_name)

    # A directed edge from a child node to its parent node. label: Symbol
    Edge = Data.define(:from_id, :to_id, :label)

    # The assembled graph: a flat list of nodes and a flat list of edges.
    # nodes: Array<node>, edges: Array<Edge>
    Graph = Data.define(:nodes, :edges)
  end
end
