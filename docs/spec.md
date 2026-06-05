# activerecord_callback_lens — Implementation Spec

## 1. Project Layout

```
activerecord_callback_lens/
├── lib/
│   └── activerecord_callback_lens/
│       ├── version.rb
│       ├── collector/
│       │   ├── callback_collector.rb
│       │   └── callback_definition.rb
│       ├── parser/
│       │   ├── condition_parser.rb
│       │   └── condition_tree.rb
│       ├── resolver/
│       │   └── method_resolver.rb
│       ├── graph/
│       │   ├── graph_builder.rb
│       │   └── nodes.rb
│       ├── renderer/
│       │   ├── mermaid_renderer.rb
│       │   ├── graphviz_renderer.rb
│       │   └── html_renderer.rb
│       ├── cli/
│       │   └── cli.rb
│       ├── railtie.rb
│       ├── tasks/
│       │   └── callback_lens.rake
│       └── runtime/
│           └── tracer.rb
├── activerecord_callback_lens.gemspec
└── Gemfile
```

---

## 2. Data Models

### 2.1 CallbackDefinition

Represents a single callback registered on an ActiveRecord model.

```ruby
# lib/activerecord_callback_lens/collector/callback_definition.rb
module ActiverecordCallbackLens
  module Collector
    CallbackDefinition = Data.define(
      :model,           # Class — the ActiveRecord model class
      :event,           # Symbol — :save, :create, :update, :destroy, :validation
      :phase,           # Symbol — :before, :after, :around
      :filter,          # Symbol | Proc | String — the callback body
      :raw_conditions,  # { if: [...], unless: [...] } — raw arrays from AR internals
      :condition_tree,  # ConditionTree::Node | nil — parsed logical tree
      :source_location  # [String, Integer] | nil — file and line of the filter
    )
  end
end
```

**Notes:**
- `event` + `phase` together reconstruct the full callback name (e.g., `:before` + `:save` → `before_save`).
- `raw_conditions` stores the unprocessed `if`/`unless` arrays extracted from ActiveRecord's internal callback chain before parsing.
- `condition_tree` is `nil` when no conditions exist.

### 2.2 ConditionTree Nodes

All nodes live under `ActiverecordCallbackLens::Parser::ConditionTree`.

```ruby
# lib/activerecord_callback_lens/parser/condition_tree.rb
module ActiverecordCallbackLens
  module Parser
    module ConditionTree
      # Base
      Node = Data.define(:children)

      # Logical combinators
      AndNode  = Data.define(:children)  # children: Array<Node>
      OrNode   = Data.define(:children)  # children: Array<Node>
      NotNode  = Data.define(:child)     # child: Node

      # Leaves
      PredicateNode = Data.define(:name)      # name: String — e.g. "saved_change_to_title?"
      MethodRefNode = Data.define(:name, :expanded_tree)
      # name: String — symbol condition like :sync_required?
      # expanded_tree: Node | nil — result of MethodResolver, nil when unresolved
    end
  end
end
```

---

## 3. Collector Layer

### 3.1 Responsibilities

- Enumerate all callbacks registered on a given model class using ActiveRecord's internal chain accessors.
- Extract condition arrays (`if`, `unless`) from each `ActiveSupport::Callbacks::Callback` object.
- Resolve `source_location` for Proc/Lambda filters.
- Return an array of `CallbackDefinition` structs.

### 3.2 API

```ruby
module ActiverecordCallbackLens
  module Collector
    class CallbackCollector
      # @param model_class [Class] an ActiveRecord::Base subclass
      # @return [Array<CallbackDefinition>]
      def self.collect(model_class)
        new(model_class).collect
      end

      def initialize(model_class)
        @model_class = model_class
      end

      def collect
        EVENTS.flat_map { |event| collect_event(event) }
      end

      private

      EVENTS = %i[save create update destroy validation].freeze

      CHAIN_METHODS = {
        save:       :_save_callbacks,
        create:     :_create_callbacks,
        update:     :_update_callbacks,
        destroy:    :_destroy_callbacks,
        validation: :_validation_callbacks,
      }.freeze

      def collect_event(event)
        chain = @model_class.send(CHAIN_METHODS[event])
        chain.map { |cb| build_definition(cb, event) }
      end

      def build_definition(cb, event)
        filter = cb.filter
        CallbackDefinition.new(
          model:          @model_class,
          event:          event,
          phase:          cb.kind,           # :before | :after | :around
          filter:         filter,
          raw_conditions: extract_conditions(cb),
          condition_tree: nil,               # populated by Parser
          source_location: resolve_location(filter),
        )
      end

      def extract_conditions(cb)
        {
          if:     Array(cb.instance_variable_get(:@if)),
          unless: Array(cb.instance_variable_get(:@unless)),
        }
      end

      def resolve_location(filter)
        case filter
        when Proc   then filter.source_location
        when Symbol then nil   # resolved later by MethodResolver
        end
      end
    end
  end
end
```

### 3.3 ActiveRecord Internals Contract

| Accessor | Callback type |
|---|---|
| `_save_callbacks` | `before_save`, `after_save`, `around_save` |
| `_create_callbacks` | `before_create`, `after_create`, `around_create` |
| `_update_callbacks` | `before_update`, `after_update`, `around_update` |
| `_destroy_callbacks` | `before_destroy`, `after_destroy`, `around_destroy` |
| `_validation_callbacks` | `before_validation`, `after_validation` |

Each callback object exposes:
- `#kind` → `:before | :after | :around`
- `#filter` → `Symbol | Proc | String`
- `@if` / `@unless` → `Array<Symbol | Proc>`

---

## 4. Prism Parser

### 4.1 Responsibilities

- Accept a `CallbackDefinition` with `raw_conditions`.
- For each condition entry (Proc/Lambda), retrieve source via `source_location` and parse the source file with Prism.
- Locate the target lambda/proc node in the AST by line number.
- Recursively walk the AST, converting `&&`, `||`, `!` and method calls into `ConditionTree` nodes.
- For Symbol conditions, emit a `MethodRefNode` (expansion delegated to `MethodResolver`).
- Return a new `CallbackDefinition` with `condition_tree` set.

### 4.2 API

```ruby
module ActiverecordCallbackLens
  module Parser
    class ConditionParser
      # @param definition [Collector::CallbackDefinition]
      # @return [Collector::CallbackDefinition] with condition_tree populated
      def self.parse(definition)
        new(definition).parse
      end

      def parse
        tree = build_tree
        @definition.with(condition_tree: tree)
      end

      private

      def build_tree
        conditions = @definition.raw_conditions
        if_nodes    = conditions[:if].map     { |c| parse_condition(c) }
        unless_nodes = conditions[:unless].map { |c| negate(parse_condition(c)) }
        all = if_nodes + unless_nodes
        return nil if all.empty?
        all.size == 1 ? all.first : ConditionTree::AndNode.new(children: all)
      end
    end
  end
end
```

### 4.3 AST Node Mapping

| Prism node | ConditionTree node |
|---|---|
| `AndNode` | `AndNode` |
| `OrNode` | `OrNode` |
| `CallNode` with `!` receiver | `NotNode` |
| `CallNode` (predicate method) | `PredicateNode` |
| Symbol condition | `MethodRefNode` |

### 4.4 Source Extraction

```ruby
def parse_proc(proc_obj)
  file, line = proc_obj.source_location
  return nil unless file && File.exist?(file)

  result = Prism.parse_file(file)
  # Find the lambda/proc node enclosing the target line
  visitor = LambdaLocator.new(target_line: line)
  visitor.visit(result.value)
  walk(visitor.node)
end
```

`LambdaLocator` traverses the AST and returns the innermost `LambdaNode` or `BlockNode` whose location contains `target_line`.

### 4.5 Recursive AST Walker

```ruby
def walk(node)
  case node
  in Prism::AndNode
    ConditionTree::AndNode.new(children: [walk(node.left), walk(node.right)])
  in Prism::OrNode
    ConditionTree::OrNode.new(children: [walk(node.left), walk(node.right)])
  in Prism::CallNode if node.name == :!
    ConditionTree::NotNode.new(child: walk(node.receiver))
  in Prism::CallNode
    ConditionTree::PredicateNode.new(name: node.name.to_s)
  else
    nil
  end
end
```

---

## 5. Method Resolver

### 5.1 Responsibilities

- Accept a `MethodRefNode` with a symbol name (e.g., `:sync_required?`).
- Locate the method definition in the model's source file using Prism.
- Parse the method body as a `ConditionTree`.
- Recursively resolve any further `MethodRefNode`s encountered in the body.
- Guard against infinite recursion with a `visited` set and `max_depth`.

### 5.2 API

```ruby
module ActiverecordCallbackLens
  module Resolver
    class MethodResolver
      MAX_DEPTH = 5

      # @param model_class [Class]
      # @param method_name [Symbol]
      # @return [Parser::ConditionTree::Node | nil]
      def self.resolve(model_class, method_name)
        new(model_class).resolve(method_name)
      end

      def resolve(method_name, depth: 0, visited: Set.new)
        return nil if depth >= MAX_DEPTH
        return nil if visited.include?(method_name)

        visited.add(method_name)
        node = locate_and_parse(method_name)
        expand_refs(node, depth: depth + 1, visited: visited)
      end
    end
  end
end
```

### 5.3 Method Location Strategy

1. Call `@model_class.instance_method(method_name).source_location` to get `[file, line]`.
2. Parse the file with Prism.
3. Find the `DefNode` at the given line.
4. Walk the body with the same AST walker used in `ConditionParser`.

### 5.4 Cycle Detection

```ruby
# visited is passed by reference (Set); adding before recursing prevents loops.
visited.add(method_name)
resolve(child_method, depth: depth + 1, visited: visited)
```

If `max_depth` is reached, the `MethodRefNode` is left with `expanded_tree: nil` and a warning is emitted to stderr.

---

## 6. Graph Builder

### 6.1 Node Types

```ruby
module ActiverecordCallbackLens
  module Graph
    CallbackNode  = Data.define(:id, :definition)   # one per CallbackDefinition
    ConditionNode = Data.define(:id, :tree_node)     # one per ConditionTree node
    MethodNode    = Data.define(:id, :method_name)   # one per unique method name
    PredicateNode = Data.define(:id, :predicate_name)

    Edge = Data.define(:from_id, :to_id, :label)     # label: :and | :or | :not | :requires
  end
end
```

### 6.2 Build Algorithm

```ruby
class GraphBuilder
  # @param definitions [Array<Collector::CallbackDefinition>]
  # @return [Graph]
  def self.build(definitions)
    new(definitions).build
  end

  def build
    @definitions.each { |d| add_callback(d) }
    Graph.new(nodes: @nodes, edges: @edges)
  end

  private

  def add_callback(defn)
    cb_node = CallbackNode.new(id: next_id, definition: defn)
    @nodes << cb_node
    add_tree(defn.condition_tree, parent_id: cb_node.id) if defn.condition_tree
  end

  def add_tree(tree_node, parent_id:)
    case tree_node
    in ConditionTree::AndNode | ConditionTree::OrNode => n
      cond = ConditionNode.new(id: next_id, tree_node: n)
      @nodes << cond
      @edges << Edge.new(from_id: cond.id, to_id: parent_id, label: :requires)
      n.children.each { |c| add_tree(c, parent_id: cond.id) }
    in ConditionTree::NotNode => n
      add_tree(n.child, parent_id: parent_id)
    in ConditionTree::PredicateNode => n
      pred = PredicateNode.new(id: next_id, predicate_name: n.name)
      @nodes << pred
      @edges << Edge.new(from_id: pred.id, to_id: parent_id, label: :requires)
    in ConditionTree::MethodRefNode => n
      m = MethodNode.new(id: next_id, method_name: n.name)
      @nodes << m
      @edges << Edge.new(from_id: m.id, to_id: parent_id, label: :requires)
      add_tree(n.expanded_tree, parent_id: m.id) if n.expanded_tree
    end
  end
end
```

---

## 7. Execution Order Analyzer

### 7.1 Canonical Callback Order

The order Rails executes callbacks on a record save (create path):

```
before_validation
after_validation
before_save
before_create
[INSERT]
after_create
after_save
after_commit / after_rollback
```

For update:

```
before_validation
after_validation
before_save
before_update
[UPDATE]
after_update
after_save
after_commit / after_rollback
```

### 7.2 Implementation

```ruby
module ActiverecordCallbackLens
  class ExecutionOrderAnalyzer
    SAVE_ORDER = %i[
      before_validation after_validation
      before_save
      before_create
      after_create
      after_save
      after_commit
    ].freeze

    UPDATE_ORDER = %i[
      before_validation after_validation
      before_save
      before_update
      after_update
      after_save
      after_commit
    ].freeze

    # @param definitions [Array<Collector::CallbackDefinition>]
    # @param operation [Symbol] :create | :update | :destroy
    # @return [Array<Collector::CallbackDefinition>] sorted
    def self.sort(definitions, operation: :create)
      order = operation == :update ? UPDATE_ORDER : SAVE_ORDER
      definitions.sort_by do |d|
        key = :"#{d.phase}_#{d.event}"
        [order.index(key) || 999]
      end
    end
  end
end
```

---

## 8. Renderers

### 8.1 Mermaid Renderer

**Output:** A `graph TD` Mermaid diagram as a String.

```ruby
module ActiverecordCallbackLens
  module Renderer
    class MermaidRenderer
      # @param graph [Graph::Graph]
      # @return [String]
      def self.render(graph)
        new(graph).render
      end

      def render
        lines = ["graph TD"]
        lines += node_declarations
        lines += edge_declarations
        lines.join("\n")
      end

      private

      def node_declarations
        @graph.nodes.map do |n|
          label = node_label(n)
          "  #{n.id}[\"#{label}\"]"
        end
      end

      def edge_declarations
        @graph.edges.map { |e| "  #{e.from_id} --> #{e.to_id}" }
      end

      def node_label(node)
        case node
        in Graph::CallbackNode  then "#{node.definition.phase}_#{node.definition.event}"
        in Graph::PredicateNode then node.predicate_name
        in Graph::MethodNode    then node.method_name
        in Graph::ConditionNode then node.tree_node.class.name.split("::").last
        end
      end
    end
  end
end
```

### 8.2 Graphviz Renderer

**Output:** A DOT language String.

```ruby
class GraphvizRenderer
  def render
    lines = ["digraph callback_lens {", "  rankdir=LR;"]
    lines += @graph.nodes.map { |n| "  #{n.id} [label=\"#{node_label(n)}\"];" }
    lines += @graph.edges.map { |e| "  #{e.from_id} -> #{e.to_id};" }
    lines << "}"
    lines.join("\n")
  end
end
```

**SVG generation:** Shell out to `dot` if Graphviz is installed:

```ruby
def to_svg(dot_string)
  IO.popen(["dot", "-Tsvg"], "r+") do |io|
    io.write(dot_string)
    io.close_write
    io.read
  end
rescue Errno::ENOENT
  nil  # Graphviz not installed
end
```

### 8.3 HTML Renderer

**Output:** A self-contained HTML file embedding Mermaid.js via CDN.

Sections:
1. **Callback List** — table with columns: Phase, Event, Filter, Conditions.
2. **Execution Flow** — ordered list from `ExecutionOrderAnalyzer`.
3. **Dependency Tree** — nested `<ul>` built from `ConditionTree`.
4. **Mermaid Diagram** — `<pre class="mermaid">` block.
5. **Graphviz SVG** — inline `<svg>` if `dot` is available.

```ruby
class HtmlRenderer
  MERMAID_CDN = "https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"

  def render
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><meta charset="utf-8"><title>Callback Lens</title></head>
      <body>
        #{callback_table}
        #{execution_flow}
        #{dependency_trees}
        <pre class="mermaid">#{mermaid_src}</pre>
        #{svg_section}
        <script src="#{MERMAID_CDN}"></script>
        <script>mermaid.initialize({startOnLoad:true});</script>
      </body>
      </html>
    HTML
  end
end
```

---

## 9. Runtime Tracer

### 9.1 Mechanism

Uses `ActiveSupport::Notifications` to subscribe to `sql.active_record` and a custom `callback.active_record_lens` event emitted by a module prepended to the model.

```ruby
module ActiverecordCallbackLens
  module Runtime
    class Tracer
      TraceRecord = Data.define(:callback_name, :model, :duration_ms, :result)

      def self.trace(model_class, &block)
        new(model_class).trace(&block)
      end

      def trace
        records = []
        sub = ActiveSupport::Notifications.subscribe("callback.lens") do |_, start, finish, _, payload|
          records << TraceRecord.new(
            callback_name: payload[:name],
            model:         payload[:model],
            duration_ms:   ((finish - start) * 1000).round(2),
            result:        payload[:result],
          )
        end
        yield
        records
      ensure
        ActiveSupport::Notifications.unsubscribe(sub)
      end
    end
  end
end
```

### 9.2 Model Instrumentation

A module is prepended to the target model at trace time:

```ruby
def self.instrument_callbacks(model_class, definitions)
  mod = Module.new
  definitions.each do |defn|
    name = defn.filter
    next unless name.is_a?(Symbol)
    mod.define_method(name) do |*args, **kwargs|
      result = nil
      ActiveSupport::Notifications.instrument("callback.lens",
        name: name, model: self.class.name) do
        result = super(*args, **kwargs)
      end
      result
    end
  end
  model_class.prepend(mod)
end
```

---

## 10. CLI

### 10.1 Dependencies

Uses [Thor](https://github.com/erikhuda/thor) for argument parsing.

### 10.2 Interface

```ruby
module ActiverecordCallbackLens
  module CLI
    class App < Thor
      desc "analyze MODEL", "Analyze callbacks for a model class"
      option :expand,   type: :boolean, desc: "Expand method conditions recursively"
      option :mermaid,  type: :boolean, desc: "Output Mermaid diagram"
      option :graphviz, type: :boolean, desc: "Output DOT/SVG via Graphviz"
      option :html,     type: :string,  desc: "Write HTML report to FILE"
      option :trace,    type: :boolean, desc: "Enable runtime tracing (requires Rails env)"

      def analyze(model_name)
        model_class = Object.const_get(model_name)
        definitions = Collector::CallbackCollector.collect(model_class)
        definitions = definitions.map { |d| Parser::ConditionParser.parse(d) }

        if options[:expand]
          definitions = definitions.map do |d|
            Resolver::MethodResolver.expand(d, model_class)
          end
        end

        graph = Graph::GraphBuilder.build(definitions)

        puts Renderer::MermaidRenderer.render(graph)  if options[:mermaid]
        puts Renderer::GraphvizRenderer.render(graph) if options[:graphviz]

        if (path = options[:html])
          File.write(path, Renderer::HtmlRenderer.render(graph, definitions: definitions))
          puts "HTML report written to #{path}"
        end
      end
    end
  end
end
```

### 10.3 Executable

`exe/callback_lens` — thin shim:

```ruby
#!/usr/bin/env ruby
require "activerecord_callback_lens"
ActiverecordCallbackLens::CLI::App.start(ARGV)
```

---

## 11. Rake Tasks

### 11.1 Railtie

A `Railtie` auto-loads the Rake tasks when the gem is used inside a Rails application. No manual `require` is needed by the user.

```ruby
# lib/activerecord_callback_lens/railtie.rb
module ActiverecordCallbackLens
  class Railtie < Rails::Railtie
    rake_tasks do
      load File.expand_path("tasks/callback_lens.rake", __dir__)
    end
  end
end
```

`lib/activerecord_callback_lens.rb` conditionally requires the Railtie:

```ruby
require "activerecord_callback_lens/railtie" if defined?(Rails::Railtie)
```

### 11.2 Task Definitions

```rake
# lib/activerecord_callback_lens/tasks/callback_lens.rake
namespace :callback_lens do
  desc "Print callback summary for MODEL (e.g. rake callback_lens:analyze MODEL=User)"
  task analyze: :environment do
    model_class = resolve_model!(ENV["MODEL"])
    definitions = pipeline(model_class)
    graph       = Graph::GraphBuilder.build(definitions)

    puts Renderer::MermaidRenderer.render(graph)
  end

  desc "Write Mermaid diagram to STDOUT for MODEL"
  task mermaid: :environment do
    model_class = resolve_model!(ENV["MODEL"])
    puts Renderer::MermaidRenderer.render(Graph::GraphBuilder.build(pipeline(model_class)))
  end

  desc "Write Graphviz DOT to STDOUT for MODEL"
  task graphviz: :environment do
    model_class = resolve_model!(ENV["MODEL"])
    puts Renderer::GraphvizRenderer.render(Graph::GraphBuilder.build(pipeline(model_class)))
  end

  desc "Generate HTML report for MODEL (output path via OUT, default: callback_lens_report.html)"
  task html: :environment do
    model_class = resolve_model!(ENV["MODEL"])
    definitions = pipeline(model_class)
    graph       = Graph::GraphBuilder.build(definitions)
    out         = ENV.fetch("OUT", "callback_lens_report.html")
    File.write(out, Renderer::HtmlRenderer.render(graph, definitions: definitions))
    puts "Report written to #{out}"
  end

  # ── helpers ────────────────────────────────────────────────────────────────

  def resolve_model!(name)
    raise "MODEL is required. Usage: rake callback_lens:analyze MODEL=User" if name.nil?
    Object.const_get(name)
  rescue NameError
    raise "Cannot find model class '#{name}'. Make sure it is loaded."
  end

  # Collect → Parse → (optionally Expand)
  def pipeline(model_class)
    definitions = Collector::CallbackCollector.collect(model_class)
    definitions = definitions.map { |d| Parser::ConditionParser.parse(d) }
    if ENV["EXPAND"] == "true"
      definitions = definitions.map { |d| Resolver::MethodResolver.expand(d, model_class) }
    end
    definitions
  end
end
```

### 11.3 Usage

```bash
# Basic summary (Mermaid to STDOUT)
rake callback_lens:analyze MODEL=User

# Mermaid only
rake callback_lens:mermaid MODEL=Order

# Graphviz DOT
rake callback_lens:graphviz MODEL=User

# HTML report (default filename)
rake callback_lens:html MODEL=User

# HTML report with custom path
rake callback_lens:html MODEL=User OUT=tmp/user_callbacks.html

# With recursive method expansion
EXPAND=true rake callback_lens:html MODEL=User OUT=tmp/user_callbacks.html
```

### 11.4 Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `MODEL` | Yes | — | ActiveRecord model class name |
| `OUT` | No | `callback_lens_report.html` | Output path for `html` task |
| `EXPAND` | No | `false` | Set to `true` to recursively expand method conditions |

---

## 12. Error Handling

| Situation | Behavior |
|---|---|
| `source_location` returns `nil` (C-level or eval'd proc) | Skip Prism parsing; `condition_tree` remains `nil` |
| Prism parse failure | Log warning to stderr; `condition_tree` remains `nil` |
| `dot` binary not found | `GraphvizRenderer#to_svg` returns `nil`; HTML section omitted |
| `MethodResolver` exceeds `max_depth` | Leaf `MethodRefNode` has `expanded_tree: nil`; warning logged |
| Invalid model name in CLI | `NameError` rescued, friendly error message printed |

---

## 13. Dependencies

| Gem | Purpose |
|---|---|
| `prism` | Ruby AST parsing |
| `thor` | CLI argument parsing |
| `activerecord` (runtime dep) | Callback chain introspection |

Optional:
| Tool | Purpose |
|---|---|
| Graphviz (`dot`) | SVG generation from DOT output |

---

## 14. Gem Metadata (gemspec sketch)

```ruby
Gem::Specification.new do |s|
  s.name          = "activerecord_callback_lens"
  s.version       = ActiverecordCallbackLens::VERSION
  s.summary       = "X-ray your ActiveRecord callbacks"
  s.executables   = ["callback_lens"]
  s.require_paths = ["lib"]

  s.add_dependency "prism"
  s.add_dependency "thor"
  s.add_dependency "activerecord", ">= 7.0"
end
```

---

## 15. Versioned Delivery Plan

| Version | Scope |
|---|---|
| **v0.1** | `CallbackCollector`, `ConditionParser` (Prism), `MermaidRenderer`, basic CLI |
| **v0.2** | `MethodResolver` with recursive expansion and cycle detection |
| **v0.3** | `GraphvizRenderer` + SVG via `dot` |
| **v0.4** | `HtmlRenderer` with embedded Mermaid and SVG |
| **v1.0** | `RuntimeTracer` via `ActiveSupport::Notifications` |
| **v2.0** | RBS-based type analysis, cross-model dependency graph |
