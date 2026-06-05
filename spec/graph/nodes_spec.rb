# frozen_string_literal: true

RSpec.describe "ActiverecordCallbackLens::Graph node types" do
  graph_ns = ActiverecordCallbackLens::Graph

  it "defines CallbackNode with id and definition" do
    node = graph_ns::CallbackNode.new(id: "n0", definition: :defn)
    expect(node.id).to eq("n0")
    expect(node.definition).to eq(:defn)
  end

  it "defines ConditionNode with id and tree_node" do
    node = graph_ns::ConditionNode.new(id: "n1", tree_node: :tree)
    expect(node.id).to eq("n1")
    expect(node.tree_node).to eq(:tree)
  end

  it "defines MethodNode with id and method_name" do
    node = graph_ns::MethodNode.new(id: "n2", method_name: "sync?")
    expect(node.method_name).to eq("sync?")
  end

  it "defines PredicateNode with id and predicate_name" do
    node = graph_ns::PredicateNode.new(id: "n3", predicate_name: "active?")
    expect(node.predicate_name).to eq("active?")
  end

  it "defines Edge with from_id, to_id and label" do
    edge = graph_ns::Edge.new(from_id: "n1", to_id: "n0", label: :requires)
    expect(edge.from_id).to eq("n1")
    expect(edge.to_id).to eq("n0")
    expect(edge.label).to eq(:requires)
  end

  it "defines Graph with nodes and edges" do
    graph = graph_ns::Graph.new(nodes: [1], edges: [2])
    expect(graph.nodes).to eq([1])
    expect(graph.edges).to eq([2])
  end

  it "produces immutable, value-equal Data instances" do
    a = graph_ns::Edge.new(from_id: "x", to_id: "y", label: :requires)
    b = graph_ns::Edge.new(from_id: "x", to_id: "y", label: :requires)
    expect(a).to eq(b)
    expect(a).to be_frozen
  end
end
