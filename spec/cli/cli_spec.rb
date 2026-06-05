# frozen_string_literal: true

require "active_record"
require "stringio"

# A minimal in-memory model with one conditional callback, used to exercise the
# CLI's full pipeline without a database.
class CliSpecUser < ActiveRecord::Base
  self.abstract_class = true

  before_save :normalize, if: :active?

  def normalize; end
  def active?; end
end

RSpec.describe ActiverecordCallbackLens::CLI::App do
  # Runs the Thor app with the given argv, capturing stdout and stderr. Returns
  # [stdout, stderr, exit_status]; exit_status is nil unless the command exits.
  def run_cli(argv)
    out = StringIO.new
    err = StringIO.new
    status = nil
    original_out = $stdout
    original_err = $stderr
    $stdout = out
    $stderr = err
    begin
      described_class.start(argv)
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout = original_out
      $stderr = original_err
    end
    [out.string, err.string, status]
  end

  describe "analyze" do
    it "prints a Mermaid diagram to stdout for a valid model" do
      stdout, _stderr, status = run_cli(%w[analyze CliSpecUser])

      expect(status).to be_nil
      expect(stdout).to start_with("graph TD")
      expect(stdout).to include("before_save")
    end

    it "defaults to Mermaid output when --mermaid is not given" do
      stdout, = run_cli(%w[analyze CliSpecUser])
      expect(stdout).to include("graph TD")
    end

    it "still renders when --mermaid is passed explicitly" do
      stdout, = run_cli(["analyze", "CliSpecUser", "--mermaid"])
      expect(stdout).to include("graph TD")
    end

    it "prints a friendly error and exits non-zero for an unknown model" do
      stdout, stderr, status = run_cli(%w[analyze NoSuchModelXYZ])

      expect(status).to eq(1)
      expect(stderr).to include("cannot find model class 'NoSuchModelXYZ'")
      expect(stderr).not_to include("NameError")
      expect(stdout).not_to include("graph TD")
    end
  end

  describe "exit behavior" do
    it "exits on failure so error paths propagate a non-zero status" do
      expect(described_class.exit_on_failure?).to be(true)
    end
  end
end
