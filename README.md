# activerecord_callback_lens

**X-ray your ActiveRecord callbacks.**

Callbacks are easy to add and hard to reason about. `activerecord_callback_lens` statically analyzes the callbacks registered on your ActiveRecord models, parses their `if`/`unless` conditions into logical trees, and renders the result as a Mermaid diagram so you can see exactly what runs and why.

## Requirements

- Ruby >= 3.2
- ActiveRecord >= 7.0, < 9.0

## Installation

Add to your `Gemfile`:

```ruby
gem "activerecord_callback_lens"
```

Or install directly:

```sh
gem install activerecord_callback_lens
```

## Usage

### CLI

Point the `callback_lens` binary at any loaded ActiveRecord model:

```sh
callback_lens analyze User
```

This prints a Mermaid `graph TD` diagram to stdout showing every callback and its condition dependencies.

```
graph TD
  n0["before_save"]
  n1["AndNode"]
  n2["saved_change_to_title?"]
  n3["status_completed?"]
  n2 --> n1
  n3 --> n1
  n1 --> n0
```

> **Note:** The model class must be loaded before analysis. In a Rails app, run the binary inside `rails runner` or require your environment first.

### Rake task (Rails)

The gem ships a Railtie that automatically loads the `callback_lens` namespace into your Rails rake tasks:

```sh
rake callback_lens:analyze MODEL=User
rake callback_lens:mermaid  MODEL=User   # alias
```

#### Recursive method expansion

Pass `--expand` (CLI) or `EXPAND=true` (Rake) to recursively resolve symbol
callback conditions into their `ConditionTree` representations (up to 5
levels deep). Cycles and unresolvable methods are left unexpanded with a
warning printed to stderr.

```bash
# CLI
callback_lens analyze User --expand --mermaid

# Rake
rake callback_lens:analyze MODEL=User EXPAND=true
rake callback_lens:mermaid  MODEL=User EXPAND=true
```

Only the exact value `EXPAND=true` (case-insensitive) enables expansion; any
other value (`EXPAND=1`, `EXPAND=yes`, empty, or absent) leaves it off.

### Programmatic API

```ruby
require "activerecord_callback_lens"

# 1. Collect raw callback definitions
definitions = ActiverecordCallbackLens::Collector::CallbackCollector.collect(User)

# 2. Parse if/unless conditions into ConditionTrees
definitions = definitions.map { |d| ActiverecordCallbackLens::Parser::ConditionParser.parse(d) }

# 3. Build a dependency graph
graph = ActiverecordCallbackLens::Graph::GraphBuilder.build(definitions)

# 4. Render as Mermaid
puts ActiverecordCallbackLens::Renderer::MermaidRenderer.render(graph)
```

## How it works

| Layer | Class | Responsibility |
|---|---|---|
| Collector | `CallbackCollector` | Reads ActiveRecord's internal `_save_callbacks`, `_create_callbacks`, `_update_callbacks`, `_destroy_callbacks`, and `_validation_callbacks` chains |
| Parser | `ConditionParser` | Uses [Prism](https://github.com/ruby/prism) to parse `Proc`/`Lambda` conditions into `AndNode`/`OrNode`/`NotNode`/`PredicateNode` trees; `Symbol` conditions become `MethodRefNode` stubs |
| Graph | `GraphBuilder` | Assembles a DAG of `CallbackNode`, `ConditionNode`, `PredicateNode`, and `MethodNode` values |
| Renderer | `MermaidRenderer` | Serializes the graph to a Mermaid `graph TD` string |

## Condition tree nodes

| Node | Meaning |
|---|---|
| `AndNode` | All children must be true |
| `OrNode` | At least one child must be true |
| `NotNode` | Negates its child (from `unless:`) |
| `PredicateNode` | A leaf predicate call (e.g. `saved_change_to_title?`) |
| `MethodRefNode` | A Symbol condition (e.g. `:sync_required?`) — expanded in v0.2 |

## Roadmap

| Version | Feature |
|---|---|
| v0.1 | CallbackCollector, Prism condition parser, Mermaid renderer, CLI, Rake task |
| **v0.2** | MethodResolver — recursive expansion of Symbol conditions (`--expand` / `EXPAND=true`) |
| v0.3 | Graphviz / DOT renderer |
| v0.4 | HTML report (callback list, execution flow, embedded diagram) |
| v1.0 | Runtime tracer via `ActiveSupport::Notifications` |
| v2.0 | RBS analysis, cross-model dependency graph |

## License

[MIT](LICENSE)
