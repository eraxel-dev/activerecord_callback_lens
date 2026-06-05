# frozen_string_literal: true

RSpec.describe ActiverecordCallbackLens::Collector::CallbackDefinition do
  let(:attributes) do
    {
      model: Class.new,
      event: :save,
      phase: :before,
      filter: :set_default_status,
      raw_conditions: { if: %i[active?], unless: [] },
      condition_tree: nil,
      source_location: ["/app/models/user.rb", 42]
    }
  end

  it "is a Data type" do
    expect(described_class.ancestors).to include(Data)
  end

  it "exposes exactly the seven defined members in order" do
    expect(described_class.members).to eq(
      %i[model event phase filter raw_conditions condition_tree source_location]
    )
  end

  describe "construction with keyword arguments" do
    subject(:definition) { described_class.new(**attributes) }

    it "stores the model class" do
      expect(definition.model).to eq(attributes[:model])
    end

    it "stores the event symbol" do
      expect(definition.event).to eq(:save)
    end

    it "stores the phase symbol" do
      expect(definition.phase).to eq(:before)
    end

    it "stores the filter" do
      expect(definition.filter).to eq(:set_default_status)
    end

    it "stores the raw conditions hash" do
      expect(definition.raw_conditions).to eq(if: %i[active?], unless: [])
    end

    it "allows a nil condition_tree" do
      expect(definition.condition_tree).to be_nil
    end

    it "stores the source location pair" do
      expect(definition.source_location).to eq(["/app/models/user.rb", 42])
    end
  end

  it "is immutable (frozen-like Data semantics)" do
    definition = described_class.new(**attributes)
    expect(definition).not_to respond_to(:event=)
  end

  describe "#with" do
    it "returns a copy with an updated condition_tree, leaving the original unchanged" do
      original = described_class.new(**attributes)
      tree = ActiverecordCallbackLens::Parser::ConditionTree::PredicateNode.new(name: "active?")

      updated = original.with(condition_tree: tree)

      expect(updated.condition_tree).to eq(tree)
      expect(original.condition_tree).to be_nil
      expect(updated.event).to eq(original.event)
    end
  end

  it "compares equal by value" do
    a = described_class.new(**attributes)
    b = described_class.new(**attributes)
    expect(a).to eq(b)
  end

  it "raises ArgumentError when a required member is missing" do
    incomplete = attributes.except(:source_location)
    expect { described_class.new(**incomplete) }.to raise_error(ArgumentError)
  end
end
