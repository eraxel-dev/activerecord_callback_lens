# frozen_string_literal: true

require "active_record"

# An in-memory ActiveRecord model exercising every callback event, both phases
# of interest, and Proc / Symbol filters with if/unless conditions.
#
# The Proc callbacks are defined on the lines below so their source_location can
# be asserted precisely; keep them grouped and do not reformat without updating
# the expectations in the spec.
class CollectorSpecUser < ActiveRecord::Base
  self.abstract_class = true

  before_validation :set_default_status
  after_validation -> { touch_validated }

  before_save :normalize_name, if: :active?
  after_save -> { notify_saved }, unless: :silent?

  before_create :assign_token
  after_create :send_welcome

  before_update :stamp_updated_at
  after_update :log_change

  before_destroy :archive
  after_destroy :purge_cache

  def set_default_status; end
  def touch_validated; end
  def normalize_name; end
  def notify_saved; end
  def assign_token; end
  def send_welcome; end
  def stamp_updated_at; end
  def log_change; end
  def archive; end
  def purge_cache; end
  def active?; end
  def silent?; end
end

RSpec.describe ActiverecordCallbackLens::Collector::CallbackCollector do
  subject(:definitions) { described_class.collect(CollectorSpecUser) }

  it "returns an array of CallbackDefinition objects" do
    expect(definitions).to be_an(Array)
    expect(definitions).to all(be_a(ActiverecordCallbackLens::Collector::CallbackDefinition))
    expect(definitions).not_to be_empty
  end

  it "enumerates all five event types" do
    expect(definitions.map(&:event).uniq).to match_array(%i[save create update destroy validation])
  end

  it "preserves the canonical event ordering from EVENTS" do
    first_seen = definitions.map(&:event).uniq
    expect(first_seen).to eq(%i[save create update destroy validation])
  end

  it "records the model class on every definition" do
    expect(definitions.map(&:model).uniq).to eq([CollectorSpecUser])
  end

  it "leaves condition_tree nil for every definition (populated later by the Parser)" do
    expect(definitions.map(&:condition_tree).uniq).to eq([nil])
  end

  # Finds a definition by event + phase + symbol filter for targeted assertions.
  def find_def(event:, phase:, filter:)
    definitions.find { |d| d.event == event && d.phase == phase && d.filter == filter }
  end

  describe "phase extraction" do
    it "maps before callbacks to phase :before" do
      expect(find_def(event: :validation, phase: :before, filter: :set_default_status)).not_to be_nil
    end

    it "maps after callbacks to phase :after" do
      expect(find_def(event: :create, phase: :after, filter: :send_welcome)).not_to be_nil
    end
  end

  describe "filter extraction" do
    it "stores Symbol filters verbatim" do
      definition = find_def(event: :create, phase: :before, filter: :assign_token)
      expect(definition.filter).to eq(:assign_token)
    end

    it "stores Proc filters as the Proc object" do
      proc_def = definitions.find { |d| d.event == :validation && d.phase == :after && d.filter.is_a?(Proc) }
      expect(proc_def.filter).to be_a(Proc)
    end
  end

  describe "raw_conditions extraction" do
    it "captures :if conditions as an array" do
      definition = find_def(event: :save, phase: :before, filter: :normalize_name)
      expect(definition.raw_conditions[:if]).to eq(%i[active?])
      expect(definition.raw_conditions[:unless]).to eq([])
    end

    it "captures :unless conditions as an array" do
      proc_def = definitions.find do |d|
        d.event == :save && d.phase == :after && d.filter.is_a?(Proc)
      end
      expect(proc_def.raw_conditions[:unless]).to eq(%i[silent?])
    end

    # ActiveModel wraps every after_* callback body so the chain halts on a
    # false return. That guard is injected as an extra entry in the callback's
    # @if array (an ActiveSupport::Callbacks::Conditionals::Value), alongside any
    # user-supplied unless: condition stored verbatim in @unless. The collector
    # surfaces both arrays faithfully; the Parser (Task 3) decides how to handle
    # the framework-injected guard.
    it "faithfully surfaces ActiveModel's injected guard in :if for after_* callbacks" do
      proc_def = definitions.find do |d|
        d.event == :save && d.phase == :after && d.filter.is_a?(Proc)
      end
      expect(proc_def.raw_conditions[:if]).to all(
        be_a(ActiveSupport::Callbacks::Conditionals::Value)
      )
      expect(proc_def.raw_conditions[:if]).not_to be_empty
    end

    it "always returns both :if and :unless keys, even when unconditional" do
      definition = find_def(event: :destroy, phase: :before, filter: :archive)
      expect(definition.raw_conditions.keys).to contain_exactly(:if, :unless)
      expect(definition.raw_conditions[:if]).to eq([])
      expect(definition.raw_conditions[:unless]).to eq([])
    end
  end

  describe "source_location resolution" do
    it "populates source_location for Proc filters" do
      proc_def = definitions.find { |d| d.filter.is_a?(Proc) }
      expect(proc_def.source_location).to be_an(Array)
      expect(proc_def.source_location.first).to end_with("callback_collector_spec.rb")
      expect(proc_def.source_location.last).to be_a(Integer)
    end

    it "leaves source_location nil for Symbol filters" do
      definition = find_def(event: :create, phase: :before, filter: :assign_token)
      expect(definition.source_location).to be_nil
    end
  end
end

RSpec.describe ActiverecordCallbackLens::Collector::CallbackCollector, "constants and unit behavior" do
  it "enumerates the five events in a stable, frozen list" do
    expect(described_class::EVENTS).to eq(%i[save create update destroy validation])
    expect(described_class::EVENTS).to be_frozen
  end

  it "maps each event to its ActiveRecord chain accessor" do
    expect(described_class::CHAIN_METHODS).to eq(
      save: :_save_callbacks,
      create: :_create_callbacks,
      update: :_update_callbacks,
      destroy: :_destroy_callbacks,
      validation: :_validation_callbacks
    )
    expect(described_class::CHAIN_METHODS).to be_frozen
  end

  it "exposes the same set of keys in EVENTS and CHAIN_METHODS" do
    expect(described_class::CHAIN_METHODS.keys).to match_array(described_class::EVENTS)
  end

  describe ".collect" do
    it "delegates to an instance built from the model class" do
      fake_chain = []
      model = instance_double(Class)
      allow(model).to receive(:send).and_return(fake_chain)

      result = described_class.collect(model)

      expect(result).to eq([])
      expect(model).to have_received(:send).with(:_save_callbacks)
    end
  end
end
