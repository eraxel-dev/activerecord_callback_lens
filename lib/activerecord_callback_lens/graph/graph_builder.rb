# frozen_string_literal: true

require_relative "nodes"
require_relative "../parser/condition_tree"

module ActiverecordCallbackLens
  module Graph
    # Converts an array of parsed CallbackDefinition objects into a Graph.
    #
    # Each definition becomes a CallbackNode. When a definition has a
    # condition_tree, the tree is walked recursively and mapped onto graph nodes:
    #
    #   AndNode / OrNode  -> ConditionNode, then recurse into children
    #   NotNode           -> no node; recurse into the child (negation is dropped
    #                        for the v0.1 dependency view)
    #   PredicateNode     -> PredicateNode graph node
    #   MethodRefNode     -> MethodNode; recurse into expanded_tree when present
    #
    # Every condition/predicate/method node gets a +:requires+ edge pointing at
    # its parent (the callback or enclosing combinator), so edges flow from a
    # dependency up to the thing that depends on it.
    class GraphBuilder
      # @param definitions [Array<Collector::CallbackDefinition>]
      # @return [Graph::Graph]
      def self.build(definitions)
        new(definitions).build
      end

      # @param definitions [Array<Collector::CallbackDefinition>]
      def initialize(definitions)
        @definitions = definitions
        @nodes = []
        @edges = []
        @counter = 0
      end

      # @return [Graph::Graph]
      def build
        @definitions.each { |definition| add_callback(definition) }
        Graph.new(nodes: @nodes, edges: @edges)
      end

      private

      # Generates a stable, monotonically increasing node id ("n0", "n1", ...).
      #
      # @return [String]
      def next_id
        id = "n#{@counter}"
        @counter += 1
        id
      end

      # @param definition [Collector::CallbackDefinition]
      # @return [void]
      def add_callback(definition)
        callback_node = CallbackNode.new(id: next_id, definition: definition)
        @nodes << callback_node
        return unless definition.condition_tree

        add_tree(definition.condition_tree, parent_id: callback_node.id)
      end

      # Recursively maps a ConditionTree node onto graph nodes and edges.
      #
      # @param tree_node [Parser::ConditionTree::Node, nil]
      # @param parent_id [String] id of the node this subtree depends on
      # @return [void]
      def add_tree(tree_node, parent_id:)
        case tree_node
        when Parser::ConditionTree::AndNode, Parser::ConditionTree::OrNode
          add_combinator(tree_node, parent_id: parent_id)
        when Parser::ConditionTree::NotNode
          add_tree(tree_node.child, parent_id: parent_id)
        when Parser::ConditionTree::PredicateNode
          add_leaf(PredicateNode.new(id: next_id, predicate_name: tree_node.name), parent_id: parent_id)
        when Parser::ConditionTree::MethodRefNode
          add_method_ref(tree_node, parent_id: parent_id)
        end
      end

      # @param tree_node [Parser::ConditionTree::AndNode, Parser::ConditionTree::OrNode]
      # @param parent_id [String]
      # @return [void]
      def add_combinator(tree_node, parent_id:)
        condition_node = ConditionNode.new(id: next_id, tree_node: tree_node)
        @nodes << condition_node
        @edges << Edge.new(from_id: condition_node.id, to_id: parent_id, label: :requires)
        tree_node.children.each { |child| add_tree(child, parent_id: condition_node.id) }
      end

      # The +expanded_tree+ inspected here is populated upstream by
      # Resolver::MethodResolver.expand; the GraphBuilder neither resolves nor
      # mutates it. When the tree was not run through expand (the v0.1 path),
      # +expanded_tree+ is nil and the MethodNode stays a leaf, so unexpanded
      # output is byte-for-byte identical to v0.1.
      #
      # @param tree_node [Parser::ConditionTree::MethodRefNode]
      # @param parent_id [String]
      # @return [void]
      def add_method_ref(tree_node, parent_id:)
        method_node = MethodNode.new(id: next_id, method_name: tree_node.name)
        @nodes << method_node
        @edges << Edge.new(from_id: method_node.id, to_id: parent_id, label: :requires)
        return unless tree_node.expanded_tree

        add_tree(tree_node.expanded_tree, parent_id: method_node.id)
      end

      # Appends a leaf node and its edge to the enclosing parent.
      #
      # @param node [Graph::PredicateNode]
      # @param parent_id [String]
      # @return [void]
      def add_leaf(node, parent_id:)
        @nodes << node
        @edges << Edge.new(from_id: node.id, to_id: parent_id, label: :requires)
      end
    end
  end
end
