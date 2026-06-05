# Task 4: Graph Builder + Mermaid Renderer + CLI & Rake Tasks

## Overview

Build the output pipeline: convert parsed `CallbackDefinition` objects into a DAG, render it as a Mermaid diagram, and expose the full flow through a Thor CLI command and Rake tasks.

## Dependency

Requires Tasks 1–3 (data models, collector, parser all complete).

## Files to Create

```
exe/callback_lens
lib/activerecord_callback_lens/graph/nodes.rb
lib/activerecord_callback_lens/graph/graph_builder.rb
lib/activerecord_callback_lens/renderer/mermaid_renderer.rb
lib/activerecord_callback_lens/cli/cli.rb
lib/activerecord_callback_lens/railtie.rb
lib/activerecord_callback_lens/tasks/callback_lens.rake
```

---

## Graph Builder

### Node Types (`graph/nodes.rb`)

```ruby
CallbackNode  = Data.define(:id, :definition)
ConditionNode = Data.define(:id, :tree_node)
MethodNode    = Data.define(:id, :method_name)
PredicateNode = Data.define(:id, :predicate_name)
Edge          = Data.define(:from_id, :to_id, :label)
Graph         = Data.define(:nodes, :edges)
```

### Build Algorithm (`graph/graph_builder.rb`)

```ruby
GraphBuilder.build(definitions) → Graph
```

For each `CallbackDefinition`:
1. Create a `CallbackNode`
2. If `condition_tree` is present, recursively walk it:
   - `AndNode` / `OrNode` → `ConditionNode`; recurse into `children`
   - `NotNode` → recurse into `child` (no extra node)
   - `PredicateNode` → `PredicateNode` graph node
   - `MethodRefNode` → `MethodNode`; recurse into `expanded_tree` if present
3. Add `Edge` from each condition/predicate node to its parent node

---

## Mermaid Renderer

### Output Format

```
graph TD
  id["label"]
  from_id --> to_id
```

### Node Labels

| Node type | Label |
|---|---|
| `CallbackNode` | `"before_save"` / `"after_commit"` etc. (`"#{phase}_#{event}"`) |
| `ConditionNode` | `node.tree_node.class.name.split("::").last` → `"AndNode"` / `"OrNode"` |
| `PredicateNode` | `"saved_change_to_title?"` |
| `MethodNode` | `"sync_required?"` |

---

## Executable

### `exe/callback_lens`

Thin shim that delegates to the Thor app:

```ruby
#!/usr/bin/env ruby
require "activerecord_callback_lens"
ActiverecordCallbackLens::CLI::App.start(ARGV)
```

After creating the file, mark it executable:

```sh
chmod +x exe/callback_lens
```

Also declare it in the gemspec (`s.executables = ["callback_lens"]`) — already done in Task 1.

---

## CLI

### Interface (`cli/cli.rb`)

Uses [Thor](https://github.com/erikhuda/thor).

```
callback_lens analyze MODEL [--mermaid]
```

- `--mermaid` — print Mermaid diagram to stdout (default behavior for v0.1)

### Error handling

Invalid model name must be caught gracefully — no Ruby backtrace shown to the user:

```ruby
def analyze(model_name)
  model_class = Object.const_get(model_name)
rescue NameError
  warn "Error: cannot find model class '#{model_name}'. Make sure it is loaded."
  exit 1
end
```

### Update entry point

After creating `cli/cli.rb`, add the following line to `lib/activerecord_callback_lens.rb`:

```ruby
require "activerecord_callback_lens/cli/cli"
```

### Full pipeline in `analyze`

```
CallbackCollector.collect → ConditionParser.parse → GraphBuilder.build → MermaidRenderer.render
```

---

## Railtie & Rake Tasks

### Railtie (`railtie.rb`)

Auto-loads rake tasks inside Rails apps. No manual `require` needed by the user.

```ruby
class Railtie < Rails::Railtie
  rake_tasks { load File.expand_path("tasks/callback_lens.rake", __dir__) }
end
```

### Rake Tasks (`tasks/callback_lens.rake`)

Two tasks for v0.1 (both depend on `:environment`):

| Task | Description |
|---|---|
| `callback_lens:analyze` | Run full pipeline and print Mermaid to stdout |
| `callback_lens:mermaid` | Alias; identical to `analyze` |

Environment variables:

| Variable | Required | Default | Description |
|---|---|---|---|
| `MODEL` | Yes | — | ActiveRecord model class name |

Error handling: if `MODEL` is missing or the class cannot be found, raise with a clear message.

---

## Error Handling (spec §12, v0.1 rows)

| Situation | Behavior |
|---|---|
| `source_location` returns `nil` (C-level or eval'd proc) | Handled in Task 3 — `condition_tree` stays `nil` |
| Prism parse failure | Handled in Task 3 — warn to `$stderr`, `condition_tree` stays `nil` |
| Invalid model name in CLI | `NameError` rescued; friendly message printed; exit non-zero |

## Update Entry Point

After creating all files in this task, `lib/activerecord_callback_lens.rb` must require them in this order (append after existing requires from Tasks 1–3):

```ruby
require "activerecord_callback_lens/graph/nodes"
require "activerecord_callback_lens/graph/graph_builder"
require "activerecord_callback_lens/renderer/mermaid_renderer"
require "activerecord_callback_lens/cli/cli"
require "activerecord_callback_lens/railtie" if defined?(Rails::Railtie)
```

---

## Acceptance Criteria

- [ ] `GraphBuilder.build(definitions)` returns a `Graph` with correct nodes and edges for a model with callbacks
- [ ] `MermaidRenderer.render(graph)` returns a valid `graph TD` Mermaid string
- [ ] `bundle exec callback_lens analyze User --mermaid` prints a Mermaid diagram to stdout
- [ ] Invalid model name prints a friendly error (no Ruby backtrace)
- [ ] `rake callback_lens:analyze MODEL=User` works inside a Rails app and prints Mermaid output
- [ ] Missing `MODEL` env var raises a descriptive error

## Spec Reference

`docs/spec.md` — Sections 6, 8.1, 10, 11
