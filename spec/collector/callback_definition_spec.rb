# frozen_string_literal: true

require_relative "../support/proc_fixtures"

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

  def definition_with(filter:)
    described_class.new(**attributes, filter: filter)
  end

  describe "#callback_name" do
    it "joins phase and event with an underscore" do
      definition = described_class.new(**attributes, phase: :before, event: :save)
      expect(definition.callback_name).to eq("before_save")
    end

    it "reflects other phase/event combinations" do
      definition = described_class.new(**attributes, phase: :after, event: :validation)
      expect(definition.callback_name).to eq("after_validation")
    end
  end

  describe "#filter_label" do
    context "with a Symbol filter" do
      it "returns the symbol name as a string" do
        expect(definition_with(filter: :set_slug).filter_label).to eq("set_slug")
      end
    end

    context "with a String filter" do
      it "returns the string unchanged" do
        expect(definition_with(filter: "do_thing").filter_label).to eq("do_thing")
      end
    end

    context "with a Proc filter" do
      it "returns \"(proc)\" by default (expand: false)" do
        expect(definition_with(filter: -> {}).filter_label).to eq("(proc)")
      end

      it "returns \"(proc)\" when expand: false is explicit" do
        expect(definition_with(filter: -> {}).filter_label(expand: false)).to eq("(proc)")
      end

      it "returns the source snippet for a real lambda when expand: true" do
        label = definition_with(filter: ProcFixtures.single_line_lambda).filter_label(expand: true)
        expect(label).to eq("-> { compute_reading_time }")
      end

      it "collapses a multi-line proc snippet onto a single line when expand: true" do
        label = definition_with(filter: ProcFixtures.multi_line_proc).filter_label(expand: true)
        expect(label).to eq("do first_step second_step end")
      end

      it "falls back to \"(proc)\" when source_location is nil" do
        no_location = -> {}
        allow(no_location).to receive(:source_location).and_return(nil)

        expect(definition_with(filter: no_location).filter_label(expand: true)).to eq("(proc)")
      end

      it "falls back to \"(proc)\" when the source file does not exist" do
        ghost = -> {}
        allow(ghost).to receive(:source_location).and_return(["/no/such/file.rb", 1])

        expect(definition_with(filter: ghost).filter_label(expand: true)).to eq("(proc)")
      end

      it "falls back to \"(proc)\" when the proc node cannot be located in the file" do
        # Point at a real, parseable file but a line that encloses no lambda/block.
        stray = -> {}
        allow(stray).to receive(:source_location).and_return([__FILE__, 1])

        expect(definition_with(filter: stray).filter_label(expand: true)).to eq("(proc)")
      end
    end
  end
end
