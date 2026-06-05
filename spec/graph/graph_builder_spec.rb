# frozen_string_literal: true

RSpec.describe ActiverecordCallbackLens::Graph::GraphBuilder do
  graph_ns = ActiverecordCallbackLens::Graph
  tree = ActiverecordCallbackLens::Parser::ConditionTree

  # Builds a CallbackDefinition with the given condition_tree; the other members
  # are irrelevant to the builder and fixed here.
  def build_definition(event: :save, phase: :before, condition_tree: nil)
    ActiverecordCallbackLens::Collector::CallbackDefinition.new(
      model: Object,
      event: event,
      phase: phase,
      filter: :placeholder,
      raw_conditions: { if: [], unless: [] },
      condition_tree: condition_tree,
      source_location: nil
    )
  end

  describe ".build" do
    it "returns a Graph value" do
      graph = described_class.build([])
      expect(graph).to be_a(graph_ns::Graph)
    end

    it "returns an empty graph for an empty definition list" do
      graph = described_class.build([])
      expect(graph.nodes).to eq([])
      expect(graph.edges).to eq([])
    end
  end

  describe "callback nodes" do
    it "creates one CallbackNode per definition" do
      graph = described_class.build([build_definition, build_definition(event: :create)])
      callback_nodes = graph.nodes.grep(graph_ns::CallbackNode)
      expect(callback_nodes.size).to eq(2)
    end

    it "assigns unique ids to every node" do
      tree_node = tree::AndNode.new(children: [tree::PredicateNode.new(name: "a?")])
      graph = described_class.build([build_definition(condition_tree: tree_node)])
      ids = graph.nodes.map(&:id)
      expect(ids).to eq(ids.uniq)
    end

    it "carries the definition on the CallbackNode" do
      definition = build_definition
      graph = described_class.build([definition])
      callback_node = graph.nodes.first
      expect(callback_node).to be_a(graph_ns::CallbackNode)
      expect(callback_node.definition).to eq(definition)
    end

    it "adds no edges for a definition without a condition tree" do
      graph = described_class.build([build_definition])
      expect(graph.edges).to be_empty
    end
  end

  describe "predicate conditions" do
    it "creates a PredicateNode and a :requires edge to its callback" do
      definition = build_definition(condition_tree: tree::PredicateNode.new(name: "active?"))
      graph = described_class.build([definition])

      callback_node = graph.nodes.find { |n| n.is_a?(graph_ns::CallbackNode) }
      predicate_node = graph.nodes.find { |n| n.is_a?(graph_ns::PredicateNode) }

      expect(predicate_node.predicate_name).to eq("active?")
      expect(graph.edges).to contain_exactly(
        graph_ns::Edge.new(from_id: predicate_node.id, to_id: callback_node.id, label: :requires)
      )
    end
  end

  describe "method-ref conditions" do
    it "creates a MethodNode and a :requires edge to its callback" do
      definition = build_definition(
        condition_tree: tree::MethodRefNode.new(name: "sync_required?", expanded_tree: nil)
      )
      graph = described_class.build([definition])

      callback_node = graph.nodes.find { |n| n.is_a?(graph_ns::CallbackNode) }
      method_node = graph.nodes.find { |n| n.is_a?(graph_ns::MethodNode) }

      expect(method_node.method_name).to eq("sync_required?")
      expect(graph.edges).to contain_exactly(
        graph_ns::Edge.new(from_id: method_node.id, to_id: callback_node.id, label: :requires)
      )
    end

    it "recurses into expanded_tree when present" do
      expanded = tree::PredicateNode.new(name: "inner?")
      definition = build_definition(
        condition_tree: tree::MethodRefNode.new(name: "outer?", expanded_tree: expanded)
      )
      graph = described_class.build([definition])

      method_node = graph.nodes.find { |n| n.is_a?(graph_ns::MethodNode) }
      predicate_node = graph.nodes.find { |n| n.is_a?(graph_ns::PredicateNode) }

      expect(predicate_node.predicate_name).to eq("inner?")
      expect(graph.edges).to include(
        graph_ns::Edge.new(from_id: predicate_node.id, to_id: method_node.id, label: :requires)
      )
    end
  end

  describe "combinator conditions" do
    it "creates a ConditionNode for AndNode and recurses into children" do
      tree_node = tree::AndNode.new(
        children: [tree::PredicateNode.new(name: "a?"), tree::PredicateNode.new(name: "b?")]
      )
      graph = described_class.build([build_definition(condition_tree: tree_node)])

      condition_node = graph.nodes.find { |n| n.is_a?(graph_ns::ConditionNode) }
      predicate_nodes = graph.nodes.grep(graph_ns::PredicateNode)
      callback_node = graph.nodes.find { |n| n.is_a?(graph_ns::CallbackNode) }

      expect(condition_node.tree_node).to eq(tree_node)
      expect(predicate_nodes.map(&:predicate_name)).to contain_exactly("a?", "b?")

      # condition node depends on the callback; predicates depend on the condition node
      expect(graph.edges).to include(
        graph_ns::Edge.new(from_id: condition_node.id, to_id: callback_node.id, label: :requires)
      )
      predicate_nodes.each do |predicate_node|
        expect(graph.edges).to include(
          graph_ns::Edge.new(from_id: predicate_node.id, to_id: condition_node.id, label: :requires)
        )
      end
    end

    it "creates a ConditionNode for OrNode" do
      tree_node = tree::OrNode.new(children: [tree::PredicateNode.new(name: "a?")])
      graph = described_class.build([build_definition(condition_tree: tree_node)])

      condition_node = graph.nodes.find { |n| n.is_a?(graph_ns::ConditionNode) }
      expect(condition_node.tree_node).to be_a(tree::OrNode)
    end
  end

  describe "NotNode handling" do
    it "drops the negation node and links the child directly to the parent" do
      tree_node = tree::NotNode.new(child: tree::PredicateNode.new(name: "published?"))
      definition = build_definition(condition_tree: tree_node)
      graph = described_class.build([definition])

      # No ConditionNode is created for the NotNode itself.
      expect(graph.nodes.none?(graph_ns::ConditionNode)).to be(true)

      callback_node = graph.nodes.find { |n| n.is_a?(graph_ns::CallbackNode) }
      predicate_node = graph.nodes.find { |n| n.is_a?(graph_ns::PredicateNode) }
      expect(predicate_node.predicate_name).to eq("published?")
      expect(graph.edges).to contain_exactly(
        graph_ns::Edge.new(from_id: predicate_node.id, to_id: callback_node.id, label: :requires)
      )
    end
  end

  describe "nested structure (a? && b?) || !c?" do
    it "builds the full node and edge set" do
      tree_node = tree::OrNode.new(
        children: [
          tree::AndNode.new(
            children: [tree::PredicateNode.new(name: "a?"), tree::PredicateNode.new(name: "b?")]
          ),
          tree::NotNode.new(child: tree::PredicateNode.new(name: "c?"))
        ]
      )
      graph = described_class.build([build_definition(condition_tree: tree_node)])

      condition_nodes = graph.nodes.grep(graph_ns::ConditionNode)
      predicate_nodes = graph.nodes.grep(graph_ns::PredicateNode)

      # One OrNode + one AndNode = two ConditionNodes; a?, b?, c? = three predicates.
      expect(condition_nodes.size).to eq(2)
      expect(predicate_nodes.map(&:predicate_name)).to contain_exactly("a?", "b?", "c?")
      # callback + 2 conditions + 3 predicates = 6 nodes; 5 edges (every non-callback node has one).
      expect(graph.nodes.size).to eq(6)
      expect(graph.edges.size).to eq(5)
    end
  end
end
