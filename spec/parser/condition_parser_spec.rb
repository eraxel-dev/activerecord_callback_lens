# frozen_string_literal: true

require "stringio"

# The lambdas below are the fixtures parsed by Prism via their source_location.
# They MUST stay in this file (so source_location resolves to a real, parseable
# file) and SHOULD NOT be reformatted without re-running the suite, since the
# parser reads them by line number.
module ConditionParserFixtures
  AND_LAMBDA   = -> { saved_change_to_title? && status_completed? }
  OR_LAMBDA    = -> { draft? || archived? }
  NOT_LAMBDA   = -> { !published? }
  SINGLE_PRED  = -> { active? }
  UNLESS_PRED  = -> { silent? }
  NESTED       = -> { (a? && b?) || !c? }
  EMPTY_LAMBDA = -> {}
end

RSpec.describe ActiverecordCallbackLens::Parser::ConditionParser do
  tree = ActiverecordCallbackLens::Parser::ConditionTree
  definition_class = ActiverecordCallbackLens::Collector::CallbackDefinition

  # Builds a CallbackDefinition with only raw_conditions varying; everything else
  # is fixed and irrelevant to the parser under test.
  def build_definition(if_conditions: [], unless_conditions: [])
    ActiverecordCallbackLens::Collector::CallbackDefinition.new(
      model: Object,
      event: :save,
      phase: :before,
      filter: :placeholder,
      raw_conditions: { if: if_conditions, unless: unless_conditions },
      condition_tree: nil,
      source_location: nil
    )
  end

  describe ".parse" do
    it "returns a new CallbackDefinition (does not mutate the input)" do
      original = build_definition
      result = described_class.parse(original)

      expect(result).to be_a(definition_class)
      expect(result).not_to equal(original)
      expect(original.condition_tree).to be_nil
    end

    it "preserves every other member of the definition" do
      original = build_definition(if_conditions: [:active?])
      result = described_class.parse(original)

      expect(result.model).to eq(original.model)
      expect(result.event).to eq(original.event)
      expect(result.phase).to eq(original.phase)
      expect(result.filter).to eq(original.filter)
      expect(result.raw_conditions).to eq(original.raw_conditions)
      expect(result.source_location).to eq(original.source_location)
    end
  end

  describe "no conditions" do
    it "leaves condition_tree nil when both arrays are empty" do
      result = described_class.parse(build_definition)
      expect(result.condition_tree).to be_nil
    end
  end

  describe "Symbol conditions" do
    it "maps a Symbol to a MethodRefNode with a nil expanded_tree" do
      result = described_class.parse(build_definition(if_conditions: [:sync_required?]))
      node = result.condition_tree

      expect(node).to be_a(tree::MethodRefNode)
      expect(node.name).to eq("sync_required?")
      expect(node.expanded_tree).to be_nil
    end
  end

  describe "Proc conditions" do
    it "parses `a? && b?` into an AndNode of two PredicateNodes" do
      result = described_class.parse(
        build_definition(if_conditions: [ConditionParserFixtures::AND_LAMBDA])
      )
      node = result.condition_tree

      expect(node).to be_a(tree::AndNode)
      expect(node.children).to all(be_a(tree::PredicateNode))
      expect(node.children.map(&:name)).to contain_exactly("saved_change_to_title?", "status_completed?")
    end

    it "parses `a? || b?` into an OrNode of two PredicateNodes" do
      result = described_class.parse(
        build_definition(if_conditions: [ConditionParserFixtures::OR_LAMBDA])
      )
      node = result.condition_tree

      expect(node).to be_a(tree::OrNode)
      expect(node.children.map(&:name)).to contain_exactly("draft?", "archived?")
    end

    it "parses `!a?` into a NotNode wrapping a PredicateNode" do
      result = described_class.parse(
        build_definition(if_conditions: [ConditionParserFixtures::NOT_LAMBDA])
      )
      node = result.condition_tree

      expect(node).to be_a(tree::NotNode)
      expect(node.child).to be_a(tree::PredicateNode)
      expect(node.child.name).to eq("published?")
    end

    it "parses a single predicate proc into a bare PredicateNode" do
      result = described_class.parse(
        build_definition(if_conditions: [ConditionParserFixtures::SINGLE_PRED])
      )
      node = result.condition_tree

      expect(node).to be_a(tree::PredicateNode)
      expect(node.name).to eq("active?")
    end

    it "parses nested boolean structure `(a? && b?) || !c?`" do
      result = described_class.parse(
        build_definition(if_conditions: [ConditionParserFixtures::NESTED])
      )
      node = result.condition_tree

      expect(node).to be_a(tree::OrNode)
      left, right = node.children
      expect(left).to be_a(tree::AndNode)
      expect(left.children.map(&:name)).to contain_exactly("a?", "b?")
      expect(right).to be_a(tree::NotNode)
      expect(right.child.name).to eq("c?")
    end

    it "yields a nil subtree for an empty proc body" do
      result = described_class.parse(
        build_definition(if_conditions: [ConditionParserFixtures::EMPTY_LAMBDA])
      )
      expect(result.condition_tree).to be_nil
    end
  end

  describe "unless conditions" do
    it "wraps a Symbol unless condition in a NotNode" do
      result = described_class.parse(build_definition(unless_conditions: [:silent?]))
      node = result.condition_tree

      expect(node).to be_a(tree::NotNode)
      expect(node.child).to be_a(tree::MethodRefNode)
      expect(node.child.name).to eq("silent?")
    end

    it "wraps a Proc unless condition in a NotNode" do
      result = described_class.parse(
        build_definition(unless_conditions: [ConditionParserFixtures::UNLESS_PRED])
      )
      node = result.condition_tree

      expect(node).to be_a(tree::NotNode)
      expect(node.child).to be_a(tree::PredicateNode)
      expect(node.child.name).to eq("silent?")
    end
  end

  describe "combining conditions" do
    it "returns the single node directly when only one condition is present" do
      result = described_class.parse(build_definition(if_conditions: [:active?]))
      expect(result.condition_tree).to be_a(tree::MethodRefNode)
    end

    it "combines multiple conditions under a top-level AndNode" do
      result = described_class.parse(
        build_definition(if_conditions: %i[a? b?])
      )
      node = result.condition_tree

      expect(node).to be_a(tree::AndNode)
      expect(node.children.map(&:name)).to eq(%w[a? b?])
    end

    it "combines if and negated unless conditions under one AndNode" do
      result = described_class.parse(
        build_definition(if_conditions: [:a?], unless_conditions: [:b?])
      )
      node = result.condition_tree

      expect(node).to be_a(tree::AndNode)
      first, second = node.children
      expect(first).to be_a(tree::MethodRefNode)
      expect(first.name).to eq("a?")
      expect(second).to be_a(tree::NotNode)
      expect(second.child.name).to eq("b?")
    end
  end

  describe "non-Symbol, non-Proc entries" do
    it "ignores framework-injected guard objects (e.g. Conditionals::Value)" do
      guard = Object.new # neither Symbol nor Proc
      result = described_class.parse(
        build_definition(if_conditions: [guard, :only?])
      )
      node = result.condition_tree

      expect(node).to be_a(tree::MethodRefNode)
      expect(node.name).to eq("only?")
    end

    it "leaves condition_tree nil when the only entry is an unrecognized object" do
      result = described_class.parse(build_definition(if_conditions: [Object.new]))
      expect(result.condition_tree).to be_nil
    end
  end

  describe "error handling for unresolvable source" do
    # Returns a real Proc whose reported source_location is the (file, line) pair
    # given. The parser branches on `Proc === entry`, so a genuine Proc is needed;
    # eval lets us forge the source_location to point at a path we control. The
    # forged location is the entire purpose of these tests, hence the disables.
    def proc_at(file, line)
      eval("-> { whatever? }", binding, file, line) # rubocop:disable Style/EvalWithLocation
    end

    it "does not raise and leaves nil when source_location is nil" do
      bare = -> { whatever? }
      allow(bare).to receive(:source_location).and_return(nil)

      expect do
        result = described_class.parse(build_definition(if_conditions: [bare]))
        expect(result.condition_tree).to be_nil
      end.not_to raise_error
    end

    it "does not raise and leaves nil when the source file does not exist" do
      missing = proc_at("/tmp/acl_definitely_missing_#{Process.pid}.rb", 1)

      expect do
        result = described_class.parse(build_definition(if_conditions: [missing]))
        expect(result.condition_tree).to be_nil
      end.not_to raise_error
    end

    it "warns to $stderr and leaves nil on a Prism parse failure" do
      broken_path = "/tmp/acl_broken_#{Process.pid}.rb"
      File.write(broken_path, "def x(\n") # deliberate syntax error
      bad = proc_at(broken_path, 1)

      original_stderr = $stderr
      $stderr = StringIO.new
      begin
        result = described_class.parse(build_definition(if_conditions: [bad]))
        captured = $stderr.string
      ensure
        $stderr = original_stderr
        FileUtils.rm_f(broken_path)
      end

      expect(result.condition_tree).to be_nil
      expect(captured).to include("Failed to parse")
      expect(captured).to include(broken_path)
    end
  end

  describe ActiverecordCallbackLens::Parser::ConditionParser::LambdaLocator do
    it "captures the innermost block/lambda body enclosing the target line" do
      require "prism"
      source = <<~RUBY
        outer = -> {
          inner = -> { deeply_nested? }
          top_level?
        }
      RUBY
      path = "/tmp/acl_locator_#{Process.pid}.rb"
      File.write(path, source)
      begin
        result = Prism.parse_file(path)
        locator = described_class.new(target_line: 2) # the inner lambda line
        locator.visit(result.value)
        expect(locator.node).to be_a(Prism::StatementsNode)
      ensure
        FileUtils.rm_f(path)
      end
    end

    it "leaves node nil when no lambda/block encloses the target line" do
      require "prism"
      path = "/tmp/acl_locator_none_#{Process.pid}.rb"
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
