# frozen_string_literal: true

require_relative "../support/proc_fixtures"

RSpec.describe ActiverecordCallbackLens::Renderer::MermaidRenderer do
  graph_ns = ActiverecordCallbackLens::Graph
  tree = ActiverecordCallbackLens::Parser::ConditionTree

  def callback_definition(event: :save, phase: :before, filter: :placeholder)
    ActiverecordCallbackLens::Collector::CallbackDefinition.new(
      model: Object,
      event: event,
      phase: phase,
      filter: filter,
      raw_conditions: { if: [], unless: [] },
      condition_tree: nil,
      source_location: nil
    )
  end

  describe ".render" do
    it "starts with the `graph LR` header" do
      graph = graph_ns::Graph.new(nodes: [], edges: [])
      expect(described_class.render(graph).lines.first.chomp).to eq("graph LR")
    end

    it "never emits the legacy top-down `graph TD` direction" do
      callback = graph_ns::CallbackNode.new(id: "n0", definition: callback_definition)
      predicate = graph_ns::PredicateNode.new(id: "n1", predicate_name: "active?")
      edge = graph_ns::Edge.new(from_id: "n1", to_id: "n0", label: :requires)
      graph = graph_ns::Graph.new(nodes: [callback, predicate], edges: [edge])
      expect(described_class.render(graph)).not_to include("graph TD")
    end

    it "renders a CallbackNode label as `phase_event: filter`" do
      node = graph_ns::CallbackNode.new(id: "n0", definition: callback_definition(event: :save, phase: :before))
      graph = graph_ns::Graph.new(nodes: [node], edges: [])
      expect(described_class.render(graph)).to include(%(  n0["before_save: placeholder"]))
    end

    it "renders a proc filter as `(proc)` by default" do
      node = graph_ns::CallbackNode.new(id: "n0", definition: callback_definition(filter: -> {}))
      graph = graph_ns::Graph.new(nodes: [node], edges: [])
      expect(described_class.render(graph)).to include(%(  n0["before_save: (proc)"]))
    end

    it "renders a proc filter's source snippet when expand: true" do
      definition = callback_definition(filter: ProcFixtures.single_line_lambda)
      node = graph_ns::CallbackNode.new(id: "n0", definition: definition)
      graph = graph_ns::Graph.new(nodes: [node], edges: [])
      expect(described_class.render(graph, expand: true))
        .to include(%(  n0["before_save: -> { compute_reading_time }"]))
    end

    it "renders a PredicateNode label as the predicate name" do
      node = graph_ns::PredicateNode.new(id: "n1", predicate_name: "saved_change_to_title?")
      graph = graph_ns::Graph.new(nodes: [node], edges: [])
      expect(described_class.render(graph)).to include(%(  n1["saved_change_to_title?"]))
    end

    it "renders a MethodNode label as the method name" do
      node = graph_ns::MethodNode.new(id: "n2", method_name: "sync_required?")
      graph = graph_ns::Graph.new(nodes: [node], edges: [])
      expect(described_class.render(graph)).to include(%(  n2["sync_required?"]))
    end

    it "renders a ConditionNode label as the unqualified tree node class name" do
      condition_node = graph_ns::ConditionNode.new(
        id: "n3", tree_node: tree::AndNode.new(children: [])
      )
      graph = graph_ns::Graph.new(nodes: [condition_node], edges: [])
      expect(described_class.render(graph)).to include(%(  n3["AndNode"]))
    end

    it "renders edges as `from --> to` arrows" do
      edge = graph_ns::Edge.new(from_id: "n1", to_id: "n0", label: :requires)
      graph = graph_ns::Graph.new(nodes: [], edges: [edge])
      expect(described_class.render(graph)).to include("  n1 --> n0")
    end

    it "produces a complete, well-formed diagram for nodes and edges together" do
      callback = graph_ns::CallbackNode.new(id: "n0", definition: callback_definition)
      predicate = graph_ns::PredicateNode.new(id: "n1", predicate_name: "active?")
      edge = graph_ns::Edge.new(from_id: "n1", to_id: "n0", label: :requires)
      graph = graph_ns::Graph.new(nodes: [callback, predicate], edges: [edge])

      expect(described_class.render(graph)).to eq(<<~MERMAID.chomp)
        graph LR
          n0["before_save: placeholder"]
          n1["active?"]
          n1 --> n0
      MERMAID
    end

    it "escapes double quotes in a label so they cannot break the diagram" do
      node = graph_ns::PredicateNode.new(id: "n0", predicate_name: %(weird"name?))
      graph = graph_ns::Graph.new(nodes: [node], edges: [])
      expect(described_class.render(graph)).to include(%(  n0["weird&quot;name?"]))
    end
  end
end
