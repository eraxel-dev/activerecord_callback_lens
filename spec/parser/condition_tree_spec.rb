# frozen_string_literal: true

RSpec.describe ActiverecordCallbackLens::Parser::ConditionTree do
  # Bind the module to a stable name so nested `describe SomeNode` blocks (which
  # rebind `described_class`) do not break references in these shared lets.
  tree_module = ActiverecordCallbackLens::Parser::ConditionTree

  let(:predicate) { tree_module::PredicateNode.new(name: "saved_change_to_title?") }
  let(:other_predicate) { tree_module::PredicateNode.new(name: "published?") }

  describe described_class::Node do
    it "carries a children member" do
      expect(described_class.members).to eq(%i[children])
    end
  end

  describe described_class::AndNode do
    it "holds a children collection" do
      node = described_class.new(children: [])
      expect(node.children).to eq([])
    end

    it "stores multiple child nodes" do
      pred_a = ActiverecordCallbackLens::Parser::ConditionTree::PredicateNode.new(name: "a?")
      pred_b = ActiverecordCallbackLens::Parser::ConditionTree::PredicateNode.new(name: "b?")
      node = described_class.new(children: [pred_a, pred_b])
      expect(node.children).to contain_exactly(pred_a, pred_b)
    end

    it "exposes exactly the children member" do
      expect(described_class.members).to eq(%i[children])
    end
  end

  describe described_class::OrNode do
    it "holds a children collection" do
      node = described_class.new(children: [])
      expect(node.children).to eq([])
    end

    it "exposes exactly the children member" do
      expect(described_class.members).to eq(%i[children])
    end
  end

  describe described_class::NotNode do
    it "wraps a single child node" do
      child = ActiverecordCallbackLens::Parser::ConditionTree::PredicateNode.new(name: "x?")
      node = described_class.new(child: child)
      expect(node.child).to eq(child)
    end

    it "exposes exactly the child member" do
      expect(described_class.members).to eq(%i[child])
    end
  end

  describe described_class::PredicateNode do
    it "stores the predicate name" do
      expect(predicate.name).to eq("saved_change_to_title?")
    end

    it "exposes exactly the name member" do
      expect(described_class.members).to eq(%i[name])
    end
  end

  describe described_class::MethodRefNode do
    it "stores the method name and a nil expanded_tree by default in v0.1" do
      node = described_class.new(name: "sync_required?", expanded_tree: nil)
      expect(node.name).to eq("sync_required?")
      expect(node.expanded_tree).to be_nil
    end

    it "can carry an expanded_tree when resolved" do
      tree = ActiverecordCallbackLens::Parser::ConditionTree::PredicateNode.new(name: "inner?")
      node = described_class.new(name: "outer?", expanded_tree: tree)
      expect(node.expanded_tree).to eq(tree)
    end

    it "exposes exactly the name and expanded_tree members" do
      expect(described_class.members).to eq(%i[name expanded_tree])
    end
  end

  describe "value semantics across node types" do
    it "treats two PredicateNodes with the same name as equal" do
      dup = described_class::PredicateNode.new(name: "saved_change_to_title?")
      expect(predicate).to eq(dup)
    end

    it "treats PredicateNodes with different names as unequal" do
      expect(predicate).not_to eq(other_predicate)
    end

    it "builds a nested tree without error" do
      tree = described_class::OrNode.new(
        children: [
          described_class::AndNode.new(children: [predicate, other_predicate]),
          described_class::NotNode.new(child: predicate)
        ]
      )
      expect(tree.children.size).to eq(2)
      expect(tree.children.first).to be_a(described_class::AndNode)
    end
  end

  it "produces immutable nodes" do
    expect(predicate).not_to respond_to(:name=)
  end
end
