# frozen_string_literal: true

require_relative "../graph/nodes"

module ActiverecordCallbackLens
  module Renderer
    # Renders a Graph::Graph as a Mermaid `graph TD` (top-down) diagram string.
    #
    # The output is a header line followed by one declaration per node and one
    # arrow per edge:
    #
    #   graph TD
    #     n0["before_save"]
    #     n1["active?"]
    #     n1 --> n0
    #
    # Node labels are derived from the node type (see #node_label) and are
    # escaped so that quotes in a predicate or method name cannot break the
    # surrounding Mermaid label syntax.
    class MermaidRenderer
      # @param graph [Graph::Graph]
      # @return [String]
      def self.render(graph)
        new(graph).render
      end

      # @param graph [Graph::Graph]
      def initialize(graph)
        @graph = graph
      end

      # @return [String]
      def render
        lines = ["graph TD"]
        lines.concat(node_declarations)
        lines.concat(edge_declarations)
        lines.join("\n")
      end

      private

      # @return [Array<String>]
      def node_declarations
        @graph.nodes.map { |node| "  #{node.id}[\"#{escape(node_label(node))}\"]" }
      end

      # @return [Array<String>]
      def edge_declarations
        @graph.edges.map { |edge| "  #{edge.from_id} --> #{edge.to_id}" }
      end

      # Derives the human-readable label for a graph node from its type.
      #
      # @param node [Graph::CallbackNode, Graph::PredicateNode, Graph::MethodNode, Graph::ConditionNode]
      # @return [String]
      def node_label(node)
        case node
        when Graph::CallbackNode  then "#{node.definition.phase}_#{node.definition.event}"
        when Graph::PredicateNode then node.predicate_name
        when Graph::MethodNode    then node.method_name
        when Graph::ConditionNode then node.tree_node.class.name.split("::").last
        else node.id
        end
      end

      # Escapes characters that would otherwise break a `["..."]` Mermaid label.
      # Double quotes become the Mermaid HTML entity and the escape character
      # itself is normalised so the label stays a single, valid token.
      #
      # @param label [String]
      # @return [String]
      def escape(label)
        label.to_s.gsub("\"", "&quot;")
      end
    end
  end
end
