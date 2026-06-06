# frozen_string_literal: true

require_relative "../graph/nodes"

module ActiverecordCallbackLens
  module Renderer
    # Renders a Graph::Graph as a Graphviz DOT language string.
    #
    # The output is a `digraph` block with a left-to-right rank direction, one
    # declaration per node and one arrow per edge:
    #
    #   digraph callback_lens {
    #     rankdir=LR;
    #     n0 [label="before_save"];
    #     n1 [label="active?"];
    #     n1 -> n0;
    #   }
    #
    # Node labels are derived from the node type (see #node_label) using the same
    # four-case logic as MermaidRenderer. Double quotes in a label are escaped as
    # `\"` so they cannot break the surrounding DOT label syntax.
    class GraphvizRenderer
      # @param graph [Graph::Graph]
      # @param expand [Boolean] expand proc filter labels to their source snippet
      # @return [String] DOT language string
      def self.render(graph, expand: false)
        new(graph, expand: expand).render
      end

      # @param graph [Graph::Graph]
      # @param expand [Boolean]
      def initialize(graph, expand: false)
        @graph = graph
        @expand = expand
      end

      # @return [String] DOT language string
      def render
        lines = ["digraph callback_lens {", "  rankdir=LR;"]
        lines.concat(node_declarations)
        lines.concat(edge_declarations)
        lines << "}"
        lines.join("\n")
      end

      # Shells out to the `dot` binary and returns the rendered SVG string.
      # Returns nil when Graphviz is not installed (the `dot` binary is absent
      # from PATH) rather than raising.
      #
      # @return [String, nil]
      def to_svg
        IO.popen(["dot", "-Tsvg"], "r+") do |io|
          io.write(render)
          io.close_write
          io.read
        end
      rescue Errno::ENOENT
        nil
      end

      private

      # @return [Array<String>]
      def node_declarations
        @graph.nodes.map { |node| "  #{node.id} [label=\"#{escape(node_label(node))}\"];" }
      end

      # @return [Array<String>]
      def edge_declarations
        @graph.edges.map { |edge| "  #{edge.from_id} -> #{edge.to_id};" }
      end

      # Derives the human-readable label for a graph node from its type.
      #
      # @param node [Graph::CallbackNode, Graph::PredicateNode, Graph::MethodNode, Graph::ConditionNode]
      # @return [String]
      def node_label(node)
        case node
        when Graph::CallbackNode
          "#{node.definition.callback_name}: #{node.definition.filter_label(expand: @expand)}"
        when Graph::PredicateNode then node.predicate_name
        when Graph::MethodNode    then node.method_name
        when Graph::ConditionNode then node.tree_node.class.name.split("::").last
        else node.id
        end
      end

      # Escapes characters that would otherwise break a `label="..."` DOT label.
      # Double quotes become a backslash-escaped quote so the label stays a
      # single, valid DOT token. (DOT uses `\"`, unlike Mermaid's `&quot;`.)
      #
      # @param label [String]
      # @return [String]
      def escape(label)
        label.to_s.gsub("\"", "\\\"")
      end
    end
  end
end
