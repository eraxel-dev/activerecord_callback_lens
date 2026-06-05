# Task 8: GraphvizRenderer Core

## Overview

Implement `GraphvizRenderer` — the renderer class that converts a `Graph::Graph`
into a DOT language string, plus a `to_svg` convenience method that shells out
to the `dot` binary and returns `nil` gracefully when Graphviz is not installed.
This is the renderer layer for v0.3; CLI and Rake integration are covered in
Task 9.

## Dependency

Requires Tasks 1–4 (`Graph::Graph`, `Graph::GraphBuilder`, and the node/edge
types all complete).

## Files to Modify

```
lib/activerecord_callback_lens/renderer/graphviz_renderer.rb   # CREATE
lib/activerecord_callback_lens.rb                              # add require
spec/renderer/graphviz_renderer_spec.rb                        # CREATE
```

---

## Deliverables

### 1. `GraphvizRenderer` class

Create `lib/activerecord_callback_lens/renderer/graphviz_renderer.rb`:

```ruby
# frozen_string_literal: true

require_relative "../graph/nodes"

module ActiverecordCallbackLens
  module Renderer
    class GraphvizRenderer
      # @param graph [Graph::Graph]
      # @return [String] DOT language string
      def self.render(graph)
        new(graph).render
      end

      # @param graph [Graph::Graph]
      def initialize(graph)
        @graph = graph
      end

      # @return [String] DOT language string
      def render
        lines = ["digraph callback_lens {", "  rankdir=LR;"]
        lines += @graph.nodes.map { |n| "  #{n.id} [label=\"#{escape(node_label(n))}\"];" }
        lines += @graph.edges.map { |e| "  #{e.from_id} -> #{e.to_id};" }
        lines << "}"
        lines.join("\n")
      end

      # Shells out to the `dot` binary and returns the SVG string.
      # Returns nil when Graphviz is not installed.
      #
      # @return [String, nil]
      def to_svg
        IO.popen(["dot", "-Tsvg"], "r+") do |io|
          io.write(render)
          io.close_write
          io.read
        end
      rescue Errno::ENOENT
        nil
      end

      private

      def node_label(node)
        case node
        when Graph::CallbackNode  then "#{node.definition.phase}_#{node.definition.event}"
        when Graph::PredicateNode then node.predicate_name
        when Graph::MethodNode    then node.method_name
        when Graph::ConditionNode then node.tree_node.class.name.split("::").last
        else node.id
        end
      end

      def escape(label)
        label.to_s.gsub('"', '\\"')
      end
    end
  end
end
```

### 2. Top-level require

Add to `lib/activerecord_callback_lens.rb`:

```ruby
require "activerecord_callback_lens/renderer/graphviz_renderer"
```

Place it immediately after the existing `mermaid_renderer` require.

---

## Acceptance Criteria

- `GraphvizRenderer.render(graph)` returns a String starting with
  `digraph callback_lens {` and ending with `}`.
- The second line is `  rankdir=LR;`.
- Each node produces a line of the form `  <id> [label="<label>"];`.
- Each edge produces a line of the form `  <from> -> <to>;`.
- Double quotes inside a label are escaped as `\"` so the DOT syntax stays
  valid.
- Node labels follow the same four-case logic as `MermaidRenderer`:
  - `CallbackNode` → `phase_event`
  - `PredicateNode` → `predicate_name`
  - `MethodNode` → `method_name`
  - `ConditionNode` → unqualified class name (e.g. `AndNode`)
- `to_svg` returns `nil` (not raises) when `dot` is not on PATH.
- All existing specs remain green.

---

## Specs

### `spec/renderer/graphviz_renderer_spec.rb`

| Scenario | Assertion |
|---|---|
| Empty graph | Output starts with `digraph callback_lens {` and ends with `}` |
| Empty graph | Second line is `  rankdir=LR;` |
| `CallbackNode` | Label rendered as `phase_event` |
| `PredicateNode` | Label rendered as `predicate_name` |
| `MethodNode` | Label rendered as `method_name` |
| `ConditionNode` wrapping `AndNode` | Label rendered as `AndNode` |
| Edge | Rendered as `  from_id -> to_id;` |
| Complete two-node, one-edge graph | Full DOT matches expected string exactly |
| Label containing `"` | Escaped as `\"` in output |
| `to_svg` when `dot` missing | Returns `nil` (stub `IO.popen` to raise `Errno::ENOENT`) |

---

## Risks

- **Low:** `to_svg` must not be tested with a live `dot` invocation in CI.
  Stub `IO.popen` to raise `Errno::ENOENT` to cover the nil-return path.
- **Low:** The `escape` method for DOT uses `\"` (backslash-quote), unlike
  Mermaid which uses `&quot;`. Keep them separate.
