# frozen_string_literal: true

RSpec.describe ActiverecordCallbackLens::Renderer::GraphvizRenderer do
  graph_ns = ActiverecordCallbackLens::Graph
  tree = ActiverecordCallbackLens::Parser::ConditionTree

  def callback_definition(event: :save, phase: :before)
    ActiverecordCallbackLens::Collector::CallbackDefinition.new(
      model: Object,
      event: event,
      phase: phase,
      filter: :placeholder,
      raw_conditions: { if: [], unless: [] },
      condition_tree: nil,
      source_location: nil
    )
  end

  describe ".render" do
    it "starts with the `digraph callback_lens {` header and ends with `}`" do
      graph = graph_ns::Graph.new(nodes: [], edges: [])
      dot = described_class.render(graph)
      expect(dot.lines.first.chomp).to eq("digraph callback_lens {")
      expect(dot.lines.last.chomp).to eq("}")
    end

    it "renders `  rankdir=LR;` as the second line" do
      graph = graph_ns::Graph.new(nodes: [], edges: [])
      expect(described_class.render(graph).lines[1].chomp).to eq("  rankdir=LR;")
    end

    it "renders a CallbackNode label as phase_event" do
      node = graph_ns::CallbackNode.new(id: "n0", definition: callback_definition(event: :save, phase: :before))
      graph = graph_ns::Graph.new(nodes: [node], edges: [])
      expect(described_class.render(graph)).to include(%(  n0 [label="before_save"];))
    end

    it "renders a PredicateNode label as the predicate name" do
      node = graph_ns::PredicateNode.new(id: "n1", predicate_name: "saved_change_to_title?")
      graph = graph_ns::Graph.new(nodes: [node], edges: [])
      expect(described_class.render(graph)).to include(%(  n1 [label="saved_change_to_title?"];))
    end

    it "renders a MethodNode label as the method name" do
      node = graph_ns::MethodNode.new(id: "n2", method_name: "sync_required?")
      graph = graph_ns::Graph.new(nodes: [node], edges: [])
      expect(described_class.render(graph)).to include(%(  n2 [label="sync_required?"];))
    end

    it "renders a ConditionNode label as the unqualified tree node class name" do
      condition_node = graph_ns::ConditionNode.new(
        id: "n3", tree_node: tree::AndNode.new(children: [])
      )
      graph = graph_ns::Graph.new(nodes: [condition_node], edges: [])
      expect(described_class.render(graph)).to include(%(  n3 [label="AndNode"];))
    end

    it "renders edges as `from -> to;` arrows" do
      edge = graph_ns::Edge.new(from_id: "n1", to_id: "n0", label: :requires)
      graph = graph_ns::Graph.new(nodes: [], edges: [edge])
      expect(described_class.render(graph)).to include("  n1 -> n0;")
    end

    it "produces a complete, well-formed DOT graph for nodes and edges together" do
      callback = graph_ns::CallbackNode.new(id: "n0", definition: callback_definition)
      predicate = graph_ns::PredicateNode.new(id: "n1", predicate_name: "active?")
      edge = graph_ns::Edge.new(from_id: "n1", to_id: "n0", label: :requires)
      graph = graph_ns::Graph.new(nodes: [callback, predicate], edges: [edge])

      expect(described_class.render(graph)).to eq(<<~DOT.chomp)
        digraph callback_lens {
          rankdir=LR;
          n0 [label="before_save"];
          n1 [label="active?"];
          n1 -> n0;
        }
      DOT
    end

    it "escapes double quotes in a label as `\\\"` so the DOT syntax stays valid" do
      node = graph_ns::PredicateNode.new(id: "n0", predicate_name: %(weird"name?))
      graph = graph_ns::Graph.new(nodes: [node], edges: [])
      expect(described_class.render(graph)).to include(%(  n0 [label="weird\\"name?"];))
    end
  end

  describe "#to_svg" do
    it "returns nil (does not raise) when the `dot` binary is not on PATH" do
      graph = graph_ns::Graph.new(nodes: [], edges: [])
      allow(IO).to receive(:popen).and_raise(Errno::ENOENT)
      expect(described_class.new(graph).to_svg).to be_nil
    end
  end
end
