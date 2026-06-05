# frozen_string_literal: true

RSpec.describe ActiverecordCallbackLens::ExecutionOrderAnalyzer do
  # Builds a minimal CallbackDefinition carrying only the phase/event pair the
  # analyzer sorts on; the other fields are irrelevant to ordering.
  def definition(phase:, event:)
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

  # Maps a sorted definition list back to its phase_event symbols for assertions.
  def keys(sorted)
    sorted.map { |d| :"#{d.phase}_#{d.event}" }
  end

  describe ".sort" do
    it "returns definitions in the canonical create-path order" do
      shuffled = [
        definition(phase: :after, event: :save),
        definition(phase: :before, event: :create),
        definition(phase: :before, event: :validation),
        definition(phase: :before, event: :save),
        definition(phase: :after, event: :create)
      ]

      expect(keys(described_class.sort(shuffled))).to eq(
        %i[before_validation before_save before_create after_create after_save]
      )
    end

    it "defaults to the create path when no operation is given" do
      shuffled = [
        definition(phase: :before, event: :create),
        definition(phase: :before, event: :validation)
      ]

      expect(keys(described_class.sort(shuffled)))
        .to eq(%i[before_validation before_create])
    end

    it "returns definitions in the canonical update-path order when operation: :update" do
      shuffled = [
        definition(phase: :after, event: :save),
        definition(phase: :before, event: :update),
        definition(phase: :before, event: :validation),
        definition(phase: :before, event: :save),
        definition(phase: :after, event: :update)
      ]

      expect(keys(described_class.sort(shuffled, operation: :update))).to eq(
        %i[before_validation before_save before_update after_update after_save]
      )
    end

    it "sorts unrecognised callback types to the end" do
      defs = [
        definition(phase: :before, event: :mystery),
        definition(phase: :before, event: :validation)
      ]

      expect(keys(described_class.sort(defs)))
        .to eq(%i[before_validation before_mystery])
    end

    it "uses index 999 for unrecognised callbacks" do
      expect(described_class::UNRECOGNISED_INDEX).to eq(999)
    end

    it "preserves the relative order of definitions at the same canonical position" do
      first = definition(phase: :before, event: :save)
      second = definition(phase: :before, event: :save)

      sorted = described_class.sort([first, second])

      expect(sorted).to eq([first, second])
    end

    it "preserves the relative order of multiple unrecognised callbacks" do
      a = definition(phase: :before, event: :alpha)
      b = definition(phase: :before, event: :beta)
      recognised = definition(phase: :before, event: :validation)

      sorted = described_class.sort([a, b, recognised])

      expect(sorted).to eq([recognised, a, b])
    end

    it "does not mutate the input array" do
      defs = [
        definition(phase: :after, event: :save),
        definition(phase: :before, event: :validation)
      ]
      original = defs.dup

      described_class.sort(defs)

      expect(defs).to eq(original)
    end
  end
end
