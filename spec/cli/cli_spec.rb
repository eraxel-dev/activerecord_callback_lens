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

# A model whose callback condition (:sync_required?) delegates to another
# predicate (:active?). Expansion resolves :sync_required? into a sub-tree that
# surfaces :active? as a child node, giving the expand specs an observable
# difference from the v0.1 (unexpanded) output.
class CliExpandUser < ActiveRecord::Base
  self.abstract_class = true

  before_save :normalize, if: :sync_required?

  def normalize; end

  def sync_required?
    active?
  end

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

  describe "analyze --graphviz" do
    it "prints a DOT graph starting with the digraph header" do
      stdout, _stderr, status = run_cli(%w[analyze CliSpecUser --no-mermaid --graphviz])

      expect(status).to be_nil
      expect(stdout).to start_with("digraph callback_lens {")
    end

    it "prints a DOT graph that ends with a closing brace" do
      stdout, = run_cli(%w[analyze CliSpecUser --no-mermaid --graphviz])

      expect(stdout.rstrip).to end_with("}")
    end

    it "includes the DOT header even when Mermaid output precedes it (default --mermaid)" do
      stdout, = run_cli(%w[analyze CliSpecUser --graphviz])

      expect(stdout).to include("digraph callback_lens {")
    end

    it "emits both Mermaid and DOT output when --mermaid and --graphviz are combined" do
      stdout, = run_cli(%w[analyze CliSpecUser --mermaid --graphviz])

      expect(stdout).to include("graph TD")
      expect(stdout).to include("digraph callback_lens {")
    end

    it "emits no DOT output when --graphviz is absent (existing behaviour unchanged)" do
      stdout, = run_cli(%w[analyze CliSpecUser])

      expect(stdout).not_to include("digraph")
    end
  end

  describe "analyze --expand" do
    it "expands method conditions into their resolved sub-trees" do
      stdout, = run_cli(%w[analyze CliExpandUser --expand --mermaid])

      # :sync_required? delegates to :active?; expansion surfaces active? as a node.
      expect(stdout).to start_with("graph TD")
      expect(stdout).to include("sync_required?")
      expect(stdout).to include("active?")
    end

    it "leaves method conditions unexpanded without --expand (v0.1 behaviour)" do
      stdout, = run_cli(%w[analyze CliExpandUser --mermaid])

      expect(stdout).to include("sync_required?")
      expect(stdout).not_to include("active?")
    end

    it "produces identical output to the no-flag invocation when --expand is absent" do
      with_flag, = run_cli(%w[analyze CliExpandUser --mermaid])
      without_flag, = run_cli(%w[analyze CliExpandUser])

      expect(with_flag).to eq(without_flag)
    end

    it "calls MethodResolver.expand only when --expand is passed" do
      expect(ActiverecordCallbackLens::Resolver::MethodResolver).not_to receive(:expand)
      run_cli(%w[analyze CliExpandUser --mermaid])
    end

    it "calls MethodResolver.expand for each definition when --expand is passed" do
      expect(ActiverecordCallbackLens::Resolver::MethodResolver)
        .to receive(:expand).at_least(:once).and_call_original
      run_cli(%w[analyze CliExpandUser --expand --mermaid])
    end
  end

  describe "exit behavior" do
    it "exits on failure so error paths propagate a non-zero status" do
      expect(described_class.exit_on_failure?).to be(true)
    end
  end
end
