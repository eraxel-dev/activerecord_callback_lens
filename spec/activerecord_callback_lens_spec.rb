# frozen_string_literal: true

RSpec.describe ActiverecordCallbackLens do
  it "loads the library without raising (AC1)" do
    expect { require "activerecord_callback_lens" }.not_to raise_error
  end

  it "defines the top-level namespace module" do
    expect(described_class).to be_a(Module)
  end

  it "exposes the gem version (AC2)" do
    expect(described_class::VERSION).to eq("0.1.0")
  end

  it "freezes the VERSION string literal" do
    expect(described_class::VERSION).to be_frozen
  end

  describe "constant accessibility (AC2)" do
    it "exposes Collector::CallbackDefinition" do
      expect(described_class::Collector::CallbackDefinition).to be_a(Class)
    end

    it "exposes the Parser::ConditionTree module" do
      expect(described_class::Parser::ConditionTree).to be_a(Module)
    end

    %i[Node AndNode OrNode NotNode PredicateNode MethodRefNode].each do |node|
      it "exposes Parser::ConditionTree::#{node}" do
        expect(described_class::Parser::ConditionTree.const_defined?(node)).to be(true)
        expect(described_class::Parser::ConditionTree.const_get(node)).to be_a(Class)
      end
    end
  end
end
