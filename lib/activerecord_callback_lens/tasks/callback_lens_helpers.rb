# frozen_string_literal: true

require "activerecord_callback_lens"

# Helpers backing the callback_lens Rake tasks. Extracted into a plain Ruby
# module (rather than task-local methods) so the logic is namespaced and unit
# testable without loading Rake or invoking a task.
module CallbackLensRakeHelpers
  module_function

  # Resolves an ActiveRecord model class from its name, raising a descriptive
  # error when MODEL is missing or the constant cannot be found.
  #
  # @param name [String, nil] the value of the MODEL environment variable
  # @return [Class]
  # @raise [RuntimeError] when name is nil/empty or the class is not loaded
  def resolve_model!(name)
    raise "MODEL is required. Usage: rake callback_lens:analyze MODEL=User" if name.nil? || name.empty?

    Object.const_get(name)
  rescue NameError
    raise "Cannot find model class '#{name}'. Make sure it is loaded."
  end

  # Runs the full pipeline (collect -> parse -> [expand] -> build -> render) for
  # a model.
  #
  # When +expand+ is true, every parsed definition's condition_tree has its
  # MethodRefNodes resolved into ConditionTree sub-trees via MethodResolver,
  # matching the CLI's +--expand+ behaviour. When false (the default), the
  # pipeline is identical to v0.1 output. Threading +expand+ through this single
  # helper keeps every rake task that delegates here uniform.
  #
  # @param model_class [Class]
  # @param expand [Boolean]
  # @return [String] the Mermaid diagram
  def render_mermaid(model_class, expand: false)
    definitions = ActiverecordCallbackLens::Collector::CallbackCollector.collect(model_class)
    definitions = definitions.map { |definition| ActiverecordCallbackLens::Parser::ConditionParser.parse(definition) }
    if expand
      definitions = definitions.map do |definition|
        ActiverecordCallbackLens::Resolver::MethodResolver.expand(definition, model_class)
      end
    end
    graph = ActiverecordCallbackLens::Graph::GraphBuilder.build(definitions)
    ActiverecordCallbackLens::Renderer::MermaidRenderer.render(graph, expand: expand)
  end

  # Runs the full pipeline (collect -> parse -> [expand] -> build -> render) for
  # a model and returns a Graphviz DOT language string. Mirrors +render_mermaid+
  # but uses the GraphvizRenderer; +expand+ is threaded through identically so
  # the +EXPAND=true+ rake convention applies to the graphviz task too.
  #
  # @param model_class [Class]
  # @param expand [Boolean]
  # @return [String] DOT language string
  def render_graphviz(model_class, expand: false)
    definitions = ActiverecordCallbackLens::Collector::CallbackCollector.collect(model_class)
    definitions = definitions.map { |definition| ActiverecordCallbackLens::Parser::ConditionParser.parse(definition) }
    if expand
      definitions = definitions.map do |definition|
        ActiverecordCallbackLens::Resolver::MethodResolver.expand(definition, model_class)
      end
    end
    graph = ActiverecordCallbackLens::Graph::GraphBuilder.build(definitions)
    ActiverecordCallbackLens::Renderer::GraphvizRenderer.render(graph, expand: expand)
  end

  # Runs the full pipeline (collect -> parse -> [expand] -> build) for a model and
  # returns a self-contained HTML report via HtmlRenderer. Mirrors
  # +render_mermaid+ / +render_graphviz+ but passes both the parsed definitions
  # and the assembled graph to the HtmlRenderer, which needs the definitions to
  # build the callback table, execution flow, and dependency tree. +expand+ is
  # threaded through identically so the +EXPAND=true+ rake convention applies.
  #
  # @param model_class [Class]
  # @param expand [Boolean]
  # @return [String] a complete HTML document
  def render_html(model_class, expand: false)
    definitions = ActiverecordCallbackLens::Collector::CallbackCollector.collect(model_class)
    definitions = definitions.map { |definition| ActiverecordCallbackLens::Parser::ConditionParser.parse(definition) }
    if expand
      definitions = definitions.map do |definition|
        ActiverecordCallbackLens::Resolver::MethodResolver.expand(definition, model_class)
      end
    end
    graph = ActiverecordCallbackLens::Graph::GraphBuilder.build(definitions)
    ActiverecordCallbackLens::Renderer::HtmlRenderer.render(graph, definitions: definitions, expand: expand)
  end

  # Parses the EXPAND environment variable using the strict truthy rule: only the
  # exact string "true" (case-insensitive, surrounding whitespace stripped)
  # enables expansion. Any other value ("1", "yes", "", nil) leaves it off.
  #
  # @param value [String, nil] the raw ENV["EXPAND"] value
  # @return [Boolean]
  def expand?(value)
    value.to_s.strip.downcase == "true"
  end
end
