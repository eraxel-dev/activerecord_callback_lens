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

  # Runs the full pipeline (collect -> parse -> build -> render) for a model.
  #
  # @param model_class [Class]
  # @return [String] the Mermaid diagram
  def render_mermaid(model_class)
    definitions = ActiverecordCallbackLens::Collector::CallbackCollector.collect(model_class)
    definitions = definitions.map { |definition| ActiverecordCallbackLens::Parser::ConditionParser.parse(definition) }
    graph = ActiverecordCallbackLens::Graph::GraphBuilder.build(definitions)
    ActiverecordCallbackLens::Renderer::MermaidRenderer.render(graph)
  end
end
