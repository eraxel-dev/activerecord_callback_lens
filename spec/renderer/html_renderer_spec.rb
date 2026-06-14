# frozen_string_literal: true

require_relative "../support/proc_fixtures"

RSpec.describe ActiverecordCallbackLens::Renderer::HtmlRenderer do
  graph_ns = ActiverecordCallbackLens::Graph
  tree = ActiverecordCallbackLens::Parser::ConditionTree

  def callback_definition(event: :save, phase: :before, filter: :normalize, condition_tree: nil)
    ActiverecordCallbackLens::Collector::CallbackDefinition.new(
      model: Object,
      event: event,
      phase: phase,
      filter: filter,
      raw_conditions: { if: [], unless: [] },
      condition_tree: condition_tree,
      source_location: nil
    )
  end

  let(:definition) { callback_definition }
  let(:graph) do
    node = graph_ns::CallbackNode.new(id: "n0", definition: definition)
    graph_ns::Graph.new(nodes: [node], edges: [])
  end

  # By default keep the SVG section out of the way so unrelated specs do not
  # depend on whether `dot` is installed on the host.
  before do
    allow_any_instance_of(ActiverecordCallbackLens::Renderer::GraphvizRenderer)
      .to receive(:to_svg).and_return(nil)
  end

  def render(defs = [definition], the_graph = graph, expand: false)
    described_class.render(the_graph, definitions: defs, expand: expand)
  end

  describe ".render" do
    it "starts with the <!DOCTYPE html> declaration" do
      expect(render).to start_with("<!DOCTYPE html>")
    end

    it "includes a <title> element" do
      expect(render).to include("<title>")
    end

    it "renders the callback table with Phase, Event, and Filter column headers" do
      output = render
      expect(output).to include("<th>Phase</th>")
      expect(output).to include("<th>Event</th>")
      expect(output).to include("<th>Filter</th>")
    end

    it "renders one table row per definition with phase and event cells" do
      output = render
      expect(output).to include("<td>before</td>")
      expect(output).to include("<td>save</td>")
    end

    it "includes the Execution Flow section" do
      expect(render).to include("Execution Flow")
    end

    it "labels execution flow items as `callback_name: filter_label`" do
      output = render([callback_definition(phase: :before, event: :save, filter: :normalize)])
      flow = output[%r{<ol>.*?</ol>}m]
      expect(flow).to include("<li>before_save: normalize</li>")
    end

    it "labels dependency tree headers as `callback_name: filter_label`" do
      defs = [
        callback_definition(
          phase: :before, event: :save, filter: :normalize,
          condition_tree: tree::PredicateNode.new(name: "active?")
        )
      ]
      output = render(defs)
      tree_section = output[%r{<h2>Dependency Tree</h2>.*?</ul>}m]
      expect(tree_section).to include("before_save: normalize")
    end

    it "lists callbacks in the execution flow in canonical create-path order" do
      defs = [
        callback_definition(phase: :after, event: :save),
        callback_definition(phase: :before, event: :validation)
      ]
      output = render(defs)

      flow = output[%r{<ol>.*?</ol>}m]
      expect(flow.index("before_validation")).to be < flow.index("after_save")
    end

    it "includes the Mermaid CDN <script> tag" do
      expect(render).to include(%(<script src="#{described_class::MERMAID_CDN}">))
    end

    it "renders a <pre class=\"mermaid\"> block containing Mermaid diagram output" do
      output = render
      expect(output).to include('<pre class="mermaid">')
      expect(output).to include("graph LR")
    end

    it "renders the Graphviz SVG section when #to_svg returns an SVG string" do
      allow_any_instance_of(ActiverecordCallbackLens::Renderer::GraphvizRenderer)
        .to receive(:to_svg).and_return("<svg><g/></svg>")

      output = render
      expect(output).to include("Graphviz SVG")
      expect(output).to include("<svg><g/></svg>")
    end

    it "omits the Graphviz SVG section when #to_svg returns nil" do
      output = render
      expect(output).not_to include("Graphviz SVG")
      expect(output).not_to include("<svg")
    end

    it "renders a dependency tree <ul> for a definition that has a condition_tree" do
      defs = [
        callback_definition(
          condition_tree: tree::PredicateNode.new(name: "active?")
        )
      ]
      output = render(defs)

      expect(output).to include("Dependency Tree")
      tree_section = output[%r{Dependency Tree.*?</ul>\s*<h2>}m]
      expect(tree_section).to include("<ul>")
      expect(output).to include("active?")
    end

    it "does not list definitions without a condition_tree in the dependency tree" do
      defs = [callback_definition(condition_tree: nil)]
      output = render(defs)

      tree_section = output[%r{<h2>Dependency Tree</h2>\s*<ul>\s*</ul>}m]
      expect(tree_section).not_to be_nil
    end

    it "renders nested combinators (AndNode) recursively" do
      and_node = tree::AndNode.new(
        children: [
          tree::PredicateNode.new(name: "active?"),
          tree::MethodRefNode.new(name: "sync_required?", expanded_tree: nil)
        ]
      )
      defs = [callback_definition(condition_tree: and_node)]
      output = render(defs)

      expect(output).to include("AND")
      expect(output).to include("active?")
      expect(output).to include("sync_required?")
    end

    it "recurses into an expanded MethodRefNode sub-tree" do
      method_ref = tree::MethodRefNode.new(
        name: "sync_required?",
        expanded_tree: tree::PredicateNode.new(name: "active?")
      )
      defs = [callback_definition(condition_tree: method_ref)]
      output = render(defs)

      expect(output).to include("sync_required?")
      expect(output).to include("active?")
    end

    it "HTML-escapes special characters in filter and predicate names" do
      defs = [
        callback_definition(
          filter: "weird<filter>&",
          condition_tree: tree::PredicateNode.new(name: "a<b>?")
        )
      ]
      output = render(defs)

      expect(output).to include("weird&lt;filter&gt;&amp;")
      expect(output).to include("a&lt;b&gt;?")
      expect(output).not_to include("weird<filter>&")
    end

    it "labels a Proc filter as (proc) rather than dumping the object" do
      defs = [callback_definition(filter: -> {})]
      output = render(defs)

      expect(output).to include("(proc)")
      expect(output).not_to include("#<Proc")
    end

    it "keeps the Filter as its own Callback List table column" do
      output = render([callback_definition(filter: :normalize)])
      table = output[%r{<table>.*?</table>}m]
      expect(table).to include("<td>normalize</td>")
    end

    context "with expand: true and a proc filter" do
      let(:proc_definition) do
        callback_definition(
          phase: :before, event: :save,
          filter: ProcFixtures.single_line_lambda,
          condition_tree: tree::PredicateNode.new(name: "active?")
        )
      end
      let(:proc_graph) do
        node = graph_ns::CallbackNode.new(id: "n0", definition: proc_definition)
        graph_ns::Graph.new(nodes: [node], edges: [])
      end

      def render_expanded
        described_class.render(proc_graph, definitions: [proc_definition], expand: true)
      end

      it "shows the proc snippet in the Callback List table" do
        table = render_expanded[%r{<table>.*?</table>}m]
        expect(table).to include("-&gt; { compute_reading_time }")
      end

      it "shows the proc snippet in the Execution Flow" do
        flow = render_expanded[%r{<ol>.*?</ol>}m]
        expect(flow).to include("before_save: -&gt; { compute_reading_time }")
      end

      it "shows the proc snippet in the Dependency Tree header" do
        tree_section = render_expanded[%r{<h2>Dependency Tree</h2>.*?</ul>}m]
        expect(tree_section).to include("before_save: -&gt; { compute_reading_time }")
      end

      it "reflects expand in the embedded Mermaid section" do
        mermaid = render_expanded[%r{<pre class="mermaid">.*?</pre>}m]
        expect(mermaid).to include("compute_reading_time")
      end

      it "renders (proc) in the embedded Mermaid section when expand is false" do
        output = described_class.render(proc_graph, definitions: [proc_definition], expand: false)
        mermaid = output[%r{<pre class="mermaid">.*?</pre>}m]
        expect(mermaid).to include("before_save: (proc)")
        expect(mermaid).not_to include("compute_reading_time")
      end
    end
  end
end
