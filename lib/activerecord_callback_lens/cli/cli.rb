# frozen_string_literal: true

require "thor"

require_relative "../collector/callback_collector"
require_relative "../parser/condition_parser"
require_relative "../resolver/method_resolver"
require_relative "../graph/graph_builder"
require_relative "../renderer/mermaid_renderer"
require_relative "../renderer/graphviz_renderer"

module ActiverecordCallbackLens
  module CLI
    # Thor application exposing the callback_lens command-line interface.
    #
    # It provides a single command, +analyze+, which runs the full pipeline
    # (collect -> parse -> build graph -> render) and prints the result to
    # stdout. Output format is selectable per invocation: a Mermaid diagram
    # (+--mermaid+, on by default) and/or a Graphviz DOT graph (+--graphviz+);
    # the two flags are independent and may be combined. An unknown model name
    # is reported with a friendly message and a non-zero exit status rather than
    # a Ruby backtrace.
    class App < Thor
      # Tells Thor to exit with a non-zero status when a command raises, so the
      # +exit 1+ paths below propagate a failure code to the shell.
      #
      # @return [Boolean]
      def self.exit_on_failure?
        true
      end

      desc "analyze MODEL", "Analyze callbacks for a model class and print a Mermaid and/or Graphviz diagram"
      option :mermaid, type: :boolean, default: true, desc: "Output a Mermaid diagram to stdout"
      option :graphviz, type: :boolean, default: false,
                        desc: "Output DOT graph via Graphviz to stdout"
      option :expand, type: :boolean, default: false,
                      desc: "Expand method conditions recursively (up to depth 5)"
      # Runs the analysis pipeline for +model_name+ and prints the result.
      #
      # @param model_name [String] the ActiveRecord model class name
      # @return [void]
      def analyze(model_name)
        model_class = resolve_model(model_name)
        graph = build_graph(model_class, expand: options[:expand])
        puts Renderer::MermaidRenderer.render(graph) if options[:mermaid]
        puts Renderer::GraphvizRenderer.render(graph) if options[:graphviz]
      end

      private

      # Resolves a model class by name, printing a friendly error and exiting
      # non-zero when the constant cannot be found.
      #
      # @param model_name [String]
      # @return [Class]
      def resolve_model(model_name)
        Object.const_get(model_name)
      rescue NameError
        warn "Error: cannot find model class '#{model_name}'. Make sure it is loaded."
        exit 1
      end

      # Collect -> Parse -> (optionally Expand) -> Build the dependency graph for
      # a model class.
      #
      # When +expand+ is true, every parsed definition's condition_tree has its
      # MethodRefNodes resolved into ConditionTree sub-trees via MethodResolver.
      # When false, the pipeline is identical to v0.1 output.
      #
      # @param model_class [Class]
      # @param expand [Boolean]
      # @return [Graph::Graph]
      def build_graph(model_class, expand: false)
        definitions = Collector::CallbackCollector.collect(model_class)
        definitions = definitions.map { |definition| Parser::ConditionParser.parse(definition) }
        if expand
          definitions = definitions.map { |definition| Resolver::MethodResolver.expand(definition, model_class) }
        end
        Graph::GraphBuilder.build(definitions)
      end
    end
  end
end
