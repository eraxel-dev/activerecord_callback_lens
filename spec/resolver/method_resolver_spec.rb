# frozen_string_literal: true

require "stringio"

# The classes below are the fixtures the resolver parses by reading their source
# file via source_location. They MUST stay in this file and SHOULD NOT be
# reformatted without re-running the suite, since the resolver locates each
# DefNode by its start line. Plain Ruby classes are used (no ActiveRecord
# dependency needed): MethodResolver only calls `instance_method(name)`, which
# every Class responds to.
module MethodResolverFixtures
  # Happy path: a single predicate body.
  class SimpleModel
    def sync_required? = saved_change_to_title?
  end

  # One level of nesting: a ref that resolves to a predicate.
  class NestedModel
    def sync_required? = needs_sync?
    def needs_sync? = dirty?
  end

  # Multi-level: a -> b -> c -> predicate, plus a boolean combinator.
  class MultiLevelModel
    def level_a? = level_b? && always_true?
    def level_b? = level_c?
    def level_c? = bottom?
  end

  # Direct self-cycle.
  class DirectCycleModel
    def loops? = loops?
  end

  # Indirect cycle A -> B -> A.
  class IndirectCycleModel
    def ping? = pong?
    def pong? = ping?
  end

  # A linear chain longer than MAX_DEPTH (d0 -> d1 -> ... -> d6).
  class DeepChainModel
    def d0? = d1?
    def d1? = d2?
    def d2? = d3?
    def d3? = d4?
    def d4? = d5?
    def d5? = d6?
    def d6? = bottom?
  end
end

RSpec.describe ActiverecordCallbackLens::Resolver::MethodResolver do
  tree = ActiverecordCallbackLens::Parser::ConditionTree
  fixtures = MethodResolverFixtures

  describe ".resolve" do
    it "delegates to a new instance" do
      result = described_class.resolve(fixtures::SimpleModel, :sync_required?)
      expect(result).to be_a(tree::PredicateNode)
    end
  end

  describe "happy path" do
    it "returns a PredicateNode for a simple predicate body" do
      result = described_class.resolve(fixtures::SimpleModel, :sync_required?)

      expect(result).to be_a(tree::PredicateNode)
      expect(result.name).to eq("saved_change_to_title?")
    end
  end

  describe "nested method ref (one level deep)" do
    it "returns a MethodRefNode whose expanded_tree is populated" do
      result = described_class.resolve(fixtures::NestedModel, :sync_required?)

      expect(result).to be_a(tree::MethodRefNode)
      expect(result.name).to eq("needs_sync?")
      expect(result.expanded_tree).to be_a(tree::PredicateNode)
      expect(result.expanded_tree.name).to eq("dirty?")
    end
  end

  describe "multi-level expansion" do
    it "expands each MethodRefNode recursively" do
      result = described_class.resolve(fixtures::MultiLevelModel, :level_a?)

      # level_a? body is `level_b? && always_true?`
      expect(result).to be_a(tree::AndNode)
      ref_b, pred_true = result.children
      expect(ref_b).to be_a(tree::MethodRefNode)
      expect(ref_b.name).to eq("level_b?")
      expect(pred_true).to be_a(tree::PredicateNode)
      expect(pred_true.name).to eq("always_true?")

      # level_b? -> level_c? -> bottom?
      ref_c = ref_b.expanded_tree
      expect(ref_c).to be_a(tree::MethodRefNode)
      expect(ref_c.name).to eq("level_c?")

      bottom = ref_c.expanded_tree
      expect(bottom).to be_a(tree::PredicateNode)
      expect(bottom.name).to eq("bottom?")
    end
  end

  describe "direct self-cycle" do
    it "terminates cleanly with the cycle node's expanded_tree nil" do
      result = nil
      expect do
        result = described_class.resolve(fixtures::DirectCycleModel, :loops?)
      end.not_to raise_error

      # `loops?` body is `loops?` -> a MethodRefNode whose recursion is cut by the
      # visited guard, leaving expanded_tree nil.
      expect(result).to be_a(tree::MethodRefNode)
      expect(result.name).to eq("loops?")
      expect(result.expanded_tree).to be_nil
    end
  end

  describe "indirect cycle (A -> B -> A)" do
    it "terminates cleanly with the cycle-closing node's expanded_tree nil" do
      result = nil
      expect do
        result = described_class.resolve(fixtures::IndirectCycleModel, :ping?)
      end.not_to raise_error

      # ping? -> pong? -> ping? (cut here)
      expect(result).to be_a(tree::MethodRefNode)
      expect(result.name).to eq("pong?")

      closing = result.expanded_tree
      expect(closing).to be_a(tree::MethodRefNode)
      expect(closing.name).to eq("ping?")
      expect(closing.expanded_tree).to be_nil
    end
  end

  describe "MAX_DEPTH exceeded" do
    it "stops at the cap, warns to $stderr, and leaves the deepest node unexpanded" do
      original_stderr = $stderr
      $stderr = StringIO.new
      result = nil
      begin
        result = described_class.resolve(fixtures::DeepChainModel, :d0?)
        captured = $stderr.string
      ensure
        $stderr = original_stderr
      end

      expect(captured).to include("Max resolution depth")

      # Walk down the ref chain; somewhere at the MAX_DEPTH boundary a
      # MethodRefNode must be left with expanded_tree nil.
      node = result
      node = node.expanded_tree while node.is_a?(tree::MethodRefNode) && node.expanded_tree
      expect(node).to be_a(tree::MethodRefNode)
      expect(node.expanded_tree).to be_nil
    end

    it "expands exactly MAX_DEPTH levels before cutting off" do
      original_stderr = $stderr
      $stderr = StringIO.new
      begin
        result = described_class.resolve(fixtures::DeepChainModel, :d0?)
      ensure
        $stderr = original_stderr
      end

      depth = 0
      node = result
      while node.is_a?(tree::MethodRefNode) && node.expanded_tree
        node = node.expanded_tree
        depth += 1
      end

      # Entry resolve is depth 0; each expand_refs increments. The chain is cut
      # once depth reaches MAX_DEPTH, so the number of populated levels is bounded
      # by MAX_DEPTH.
      expect(depth).to be <= described_class::MAX_DEPTH
      expect(node.expanded_tree).to be_nil
    end
  end

  describe "nil source_location" do
    it "returns nil without raising" do
      model = Class.new do
        def magic? = whatever?
      end
      meth = model.instance_method(:magic?)
      # Stub the UnboundMethod's source_location to nil (the C-level/eval case).
      allow(model).to receive(:instance_method).with(:magic?).and_return(meth)
      allow(meth).to receive(:source_location).and_return(nil)

      result = nil
      expect do
        result = described_class.resolve(model, :magic?)
      end.not_to raise_error
      expect(result).to be_nil
    end

    it "returns nil for a C-level method with no Ruby source" do
      # Integer#even? is implemented in C; its source_location is nil.
      result = described_class.resolve(Integer, :even?)
      expect(result).to be_nil
    end
  end

  describe "Prism parse failure" do
    it "returns nil and warns to $stderr" do
      broken_path = "/tmp/acl_resolver_broken_#{Process.pid}.rb"
      File.write(broken_path, "def x(\n") # deliberate syntax error

      model = Class.new do
        def broken? = whatever?
      end
      meth = model.instance_method(:broken?)
      allow(model).to receive(:instance_method).with(:broken?).and_return(meth)
      allow(meth).to receive(:source_location).and_return([broken_path, 1])

      original_stderr = $stderr
      $stderr = StringIO.new
      result = nil
      begin
        result = described_class.resolve(model, :broken?)
        captured = $stderr.string
      ensure
        $stderr = original_stderr
        FileUtils.rm_f(broken_path)
      end

      expect(result).to be_nil
      expect(captured).to include("Failed to parse")
      expect(captured).to include(broken_path)
    end
  end

  describe "an undefined method name" do
    it "returns nil without raising" do
      result = nil
      expect do
        result = described_class.resolve(fixtures::SimpleModel, :no_such_method?)
      end.not_to raise_error
      expect(result).to be_nil
    end
  end

  describe ActiverecordCallbackLens::Resolver::MethodResolver::DefLocator do
    it "captures the DefNode body starting on the target line" do
      require "prism"
      source = <<~RUBY
        class Foo
          def bar?
            baz?
          end
        end
      RUBY
      path = "/tmp/acl_def_locator_#{Process.pid}.rb"
      File.write(path, source)
      begin
        result = Prism.parse_file(path)
        locator = described_class.new(target_line: 2, method_name: :bar?)
        locator.visit(result.value)
        expect(locator.node).to be_a(Prism::StatementsNode)
      ensure
        FileUtils.rm_f(path)
      end
    end

    it "leaves node nil when no def starts on the target line" do
      require "prism"
      path = "/tmp/acl_def_locator_none_#{Process.pid}.rb"
      File.write(path, "x = 1\n")
      begin
        result = Prism.parse_file(path)
        locator = described_class.new(target_line: 99)
        locator.visit(result.value)
        expect(locator.node).to be_nil
      ensure
        FileUtils.rm_f(path)
      end
    end
  end
end
