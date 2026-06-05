# frozen_string_literal: true

require "active_record"

# Load the helper module backing the rake tasks. It is a plain Ruby module, so
# it can be required and unit tested without loading Rake or running a task.
require_relative "../../lib/activerecord_callback_lens/tasks/callback_lens_helpers"

class RakeSpecUser < ActiveRecord::Base
  self.abstract_class = true

  before_save :normalize, if: :active?

  def normalize; end
  def active?; end
end

# A model whose callback condition (:sync_required?) delegates to another
# predicate (:active?), so expansion produces an observable extra node.
class RakeExpandUser < ActiveRecord::Base
  self.abstract_class = true

  before_save :normalize, if: :sync_required?

  def normalize; end

  def sync_required?
    active?
  end

  def active?; end
end

RSpec.describe CallbackLensRakeHelpers do
  describe ".resolve_model!" do
    it "returns the constant for a valid model name" do
      expect(described_class.resolve_model!("RakeSpecUser")).to eq(RakeSpecUser)
    end

    it "raises a descriptive error when MODEL is nil" do
      expect { described_class.resolve_model!(nil) }
        .to raise_error(/MODEL is required/)
    end

    it "raises a descriptive error when MODEL is an empty string" do
      expect { described_class.resolve_model!("") }
        .to raise_error(/MODEL is required/)
    end

    it "raises a friendly error when the class cannot be found" do
      expect { described_class.resolve_model!("NoSuchModelABC") }
        .to raise_error(/Cannot find model class 'NoSuchModelABC'/)
    end
  end

  describe ".render_mermaid" do
    it "runs the full pipeline and returns a Mermaid string" do
      output = described_class.render_mermaid(RakeSpecUser)
      expect(output).to start_with("graph TD")
      expect(output).to include("before_save")
    end

    it "leaves method conditions unexpanded by default (v0.1 behaviour)" do
      output = described_class.render_mermaid(RakeExpandUser)
      expect(output).to include("sync_required?")
      expect(output).not_to include("active?")
    end

    it "produces identical output whether expand is omitted or explicitly false" do
      expect(described_class.render_mermaid(RakeExpandUser))
        .to eq(described_class.render_mermaid(RakeExpandUser, expand: false))
    end

    it "expands method conditions into resolved sub-trees when expand: true" do
      output = described_class.render_mermaid(RakeExpandUser, expand: true)
      expect(output).to include("sync_required?")
      expect(output).to include("active?")
    end

    it "calls MethodResolver.expand only when expand: true" do
      expect(ActiverecordCallbackLens::Resolver::MethodResolver).not_to receive(:expand)
      described_class.render_mermaid(RakeExpandUser, expand: false)
    end

    it "calls MethodResolver.expand for each definition when expand: true" do
      expect(ActiverecordCallbackLens::Resolver::MethodResolver)
        .to receive(:expand).at_least(:once).and_call_original
      described_class.render_mermaid(RakeExpandUser, expand: true)
    end
  end

  describe ".expand?" do
    it "returns true for the exact string \"true\"" do
      expect(described_class.expand?("true")).to be(true)
    end

    it "is case-insensitive for \"true\"" do
      expect(described_class.expand?("TRUE")).to be(true)
      expect(described_class.expand?("True")).to be(true)
    end

    it "strips surrounding whitespace before comparing" do
      expect(described_class.expand?("  true  ")).to be(true)
    end

    it "returns false for \"false\"" do
      expect(described_class.expand?("false")).to be(false)
    end

    it "returns false for \"1\" (not a recognised truthy value)" do
      expect(described_class.expand?("1")).to be(false)
    end

    it "returns false for \"yes\" (not a recognised truthy value)" do
      expect(described_class.expand?("yes")).to be(false)
    end

    it "returns false for an empty string" do
      expect(described_class.expand?("")).to be(false)
    end

    it "returns false for nil (EXPAND absent)" do
      expect(described_class.expand?(nil)).to be(false)
    end
  end
end
