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
  end
end
