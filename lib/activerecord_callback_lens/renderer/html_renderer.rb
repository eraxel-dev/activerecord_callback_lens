# frozen_string_literal: true

require "cgi"

require_relative "mermaid_renderer"
require_relative "graphviz_renderer"
require_relative "../execution_order_analyzer"
require_relative "../parser/condition_tree"

module ActiverecordCallbackLens
  module Renderer
    # Renders a single ConditionTree node (and its descendants) as nested +<ul>+
    # markup, and exposes the flat list of leaf condition names. Extracted from
    # HtmlRenderer so the recursive tree handling is a single, testable
    # responsibility separate from page assembly.
    #
    # All names are HTML escaped via CGI.escapeHTML so values containing +<+,
    # +>+ or +&+ cannot break the surrounding markup.
    class ConditionTreeHtml
      Tree = Parser::ConditionTree

      # @param node [Parser::ConditionTree::Node]
      def initialize(node)
        @node = node
      end

      # @return [String] nested <ul> markup for the node
      def to_html
        render(@node)
      end

      # @return [Array<String>] leaf names (predicate + method refs), depth-first
      def names
        leaf_names(@node)
      end

      private

      def render(node)
        case node
        when Tree::AndNode       then combinator("AND", node.children)
        when Tree::OrNode        then combinator("OR", node.children)
        when Tree::NotNode       then combinator("NOT", [node.child])
        when Tree::PredicateNode then "<ul><li>#{escape(node.name)}</li></ul>"
        when Tree::MethodRefNode then method_ref(node)
        else ""
        end
      end

      def combinator(label, children)
        items = children.map { |child| "<li>#{render(child)}</li>" }
        "<ul><li>#{escape(label)}</li>#{items.join}</ul>"
      end

      def method_ref(node)
        inner = node.expanded_tree.nil? ? "" : render(node.expanded_tree)
        "<ul><li>#{escape(node.name)}#{inner}</li></ul>"
      end

      def leaf_names(node)
        case node
        when Tree::AndNode, Tree::OrNode
          node.children.flat_map { |child| leaf_names(child) }
        when Tree::NotNode
          leaf_names(node.child)
        when Tree::PredicateNode, Tree::MethodRefNode
          [node.name]
        else
          []
        end
      end

      def escape(value)
        CGI.escapeHTML(value.to_s)
      end
    end

    # Renders a self-contained HTML report for a model's callbacks.
    #
    # The document embeds five sections (spec section 8.3):
    #
    # 1. Callback List   — a table with columns Phase, Event, Filter, Conditions.
    # 2. Execution Flow  — an ordered list sorted by ExecutionOrderAnalyzer
    #    (the +:create+ path).
    # 3. Dependency Tree — a nested +<ul>+ built from each definition's
    #    ConditionTree (via ConditionTreeHtml).
    # 4. Mermaid Diagram — a +<pre class="mermaid">+ block populated by
    #    MermaidRenderer and rendered client-side via the Mermaid CDN script.
    # 5. Graphviz SVG    — the inline +<svg>+ produced by GraphvizRenderer#to_svg
    #    when the +dot+ binary is available; the section is omitted otherwise.
    #
    # All user-derived text is HTML escaped with CGI.escapeHTML.
    class HtmlRenderer
      # The Mermaid.js bundle loaded from a CDN so the report stays a single,
      # dependency-free HTML file.
      MERMAID_CDN = "https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"

      # @param graph [Graph::Graph] the assembled dependency graph
      # @param definitions [Array<Collector::CallbackDefinition>] parsed definitions
      # @param expand [Boolean] expand proc filter labels to their source snippet
      # @return [String] a complete HTML document
      def self.render(graph, definitions:, expand: false)
        new(graph, definitions, expand: expand).render
      end

      # @param graph [Graph::Graph]
      # @param definitions [Array<Collector::CallbackDefinition>]
      # @param expand [Boolean]
      def initialize(graph, definitions, expand: false)
        @graph = graph
        @definitions = definitions
        @expand = expand
      end

      # Assembles the full HTML document.
      #
      # @return [String]
      def render
        <<~HTML
          <!DOCTYPE html>
          <html>
          <head><meta charset="utf-8"><title>Callback Lens</title></head>
          <body>
          #{callback_table}
          #{execution_flow}
          #{dependency_trees}
          #{mermaid_section}
          #{svg_section}
          <script src="#{MERMAID_CDN}"></script>
          <script>mermaid.initialize({startOnLoad:true});</script>
          </body>
          </html>
        HTML
      end

      private

      # Section 1: a table with one row per definition.
      def callback_table
        rows = @definitions.map do |definition|
          "<tr>" \
            "<td>#{escape(definition.phase)}</td>" \
            "<td>#{escape(definition.event)}</td>" \
            "<td>#{escape(definition.filter_label(expand: @expand))}</td>" \
            "<td>#{escape(conditions_label(definition))}</td>" \
            "</tr>"
        end
        <<~HTML.chomp
          <h2>Callback List</h2>
          <table>
          <thead><tr><th>Phase</th><th>Event</th><th>Filter</th><th>Conditions</th></tr></thead>
          <tbody>
          #{rows.join("\n")}
          </tbody>
          </table>
        HTML
      end

      # Section 2: callbacks in canonical create-path execution order.
      def execution_flow
        ordered = ExecutionOrderAnalyzer.sort(@definitions, operation: :create)
        items = ordered.map do |d|
          "<li>#{escape("#{d.callback_name}: #{d.filter_label(expand: @expand)}")}</li>"
        end
        <<~HTML.chomp
          <h2>Execution Flow</h2>
          <ol>
          #{items.join("\n")}
          </ol>
        HTML
      end

      # Section 3: a nested dependency tree per definition that carries a
      # condition_tree. Definitions without conditions are skipped.
      def dependency_trees
        trees = @definitions.filter_map do |definition|
          next if definition.condition_tree.nil?

          "<li>#{escape("#{definition.callback_name}: #{definition.filter_label(expand: @expand)}")}" \
            "#{ConditionTreeHtml.new(definition.condition_tree).to_html}</li>"
        end
        <<~HTML.chomp
          <h2>Dependency Tree</h2>
          <ul>
          #{trees.join("\n")}
          </ul>
        HTML
      end

      # Section 4: the Mermaid source wrapped in a client-rendered block.
      def mermaid_section
        <<~HTML.chomp
          <h2>Mermaid Diagram</h2>
          <pre class="mermaid">#{escape(MermaidRenderer.render(@graph, expand: @expand))}</pre>
        HTML
      end

      # Section 5: the inline Graphviz SVG, or an empty string when +dot+ is not
      # installed (GraphvizRenderer#to_svg returns nil).
      def svg_section
        svg = GraphvizRenderer.new(@graph, expand: @expand).to_svg
        return "" if svg.nil?

        <<~HTML.chomp
          <h2>Graphviz SVG</h2>
          <div class="graphviz">#{svg}</div>
        HTML
      end

      # A comma-joined label of a definition's condition leaf names, or "".
      def conditions_label(definition)
        tree = definition.condition_tree
        return "" if tree.nil?

        ConditionTreeHtml.new(tree).names.join(", ")
      end

      # HTML-escapes a value so it is safe to embed as element text.
      def escape(value)
        CGI.escapeHTML(value.to_s)
      end
    end
  end
end
