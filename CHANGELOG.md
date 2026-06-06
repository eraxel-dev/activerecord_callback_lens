# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.1] - 2026-06-06

### Added

- Example Rails application at `examples/blog_app/`: a self-contained demo app
  with an `Article` model that exercises all five callback lifecycle events,
  every condition style (`Proc`, `Symbol`, `AndNode`, `OrNode`, `NotNode`), and
  a predicate chain designed to show the difference between default and
  `EXPAND=true` output. Includes `User` and `Comment` models for multi-model
  demos, a `bin/callback_lens_demo` script demonstrating the programmatic API,
  and a dedicated README with the full command matrix.

## [0.4.0] - 2026-06-06

### Added

- `ExecutionOrderAnalyzer`: sorts `CallbackDefinition` arrays into the canonical
  Rails execution order for the create path (`:before_validation` →
  `after_commit`) or update path. Unrecognised callback types are placed at the
  end; relative order within the same position is preserved.
- `HtmlRenderer`: generates a self-contained HTML report containing five
  sections — a callback list table (Phase, Event, Filter, Conditions), an
  execution-order flow list, a nested dependency tree per condition, a
  client-rendered Mermaid diagram (Mermaid.js loaded from CDN), and an inline
  Graphviz SVG when `dot` is available. All user-derived text is HTML-escaped.
- `--html FILE` flag for the `analyze` CLI command: writes the HTML report to
  `FILE` in addition to any stdout output.
- `callback_lens:html` Rake task: writes the HTML report to `OUT`
  (default: `callback_lens_report.html`). Accepts the same `MODEL` and
  `EXPAND` environment variables as the other tasks.

## [0.3.0] - 2026-06-06

### Added

- `GraphvizRenderer`: converts a `Graph::Graph` to a DOT language string.
- `GraphvizRenderer#to_svg`: shells out to the `dot` binary and returns an SVG
  string; returns `nil` when Graphviz is not installed.
- `--graphviz` flag for the `analyze` CLI command (outputs DOT to stdout).
- `callback_lens:graphviz` Rake task (outputs DOT to stdout).

## [0.2.0] - 2026-06-05

### Added

- `MethodResolver`: recursively expand symbol callback conditions into
  `ConditionTree` sub-trees (up to `MAX_DEPTH = 5` levels).
- Cycle detection via a `visited` set; cyclic `MethodRefNode`s are left with
  `expanded_tree: nil`.
- `--expand` flag for the `analyze` CLI command.
- `EXPAND=true` environment variable for all Rake tasks (`analyze`, `mermaid`).

## [0.1.0] - 2026-06-05

Initial release.

### Added

- **CallbackCollector** — reads ActiveRecord's internal `_save_callbacks`, `_create_callbacks`, `_update_callbacks`, `_destroy_callbacks`, and `_validation_callbacks` chains and returns an array of `CallbackDefinition` structs with raw `if`/`unless` condition data.
- **ConditionParser** — uses [Prism](https://github.com/ruby/prism) to parse `Proc`/`Lambda` conditions into structured `ConditionTree` nodes (`AndNode`, `OrNode`, `NotNode`, `PredicateNode`). Symbol conditions become `MethodRefNode` stubs, deferred for resolution in v0.2. Gracefully skips missing or unparseable source files.
- **GraphBuilder** — assembles a directed acyclic graph (`Graph::Graph`) from parsed `CallbackDefinition` objects, producing typed `CallbackNode`, `ConditionNode`, `PredicateNode`, and `MethodNode` values connected by `Edge` records.
- **MermaidRenderer** — serializes a `Graph::Graph` to a Mermaid `graph TD` diagram string with escaped node labels.
- **CLI** (`callback_lens analyze MODEL`) — Thor-based command-line interface that runs the full collect → parse → build → render pipeline and prints the Mermaid diagram to stdout.
- **Rake task** (`callback_lens:analyze MODEL=Foo`) — Rails-integrated rake task backed by a Railtie; `callback_lens:mermaid` is provided as an alias.

[0.4.1]: https://github.com/eraxel/activerecord_callback_lens/releases/tag/v0.4.1
[0.4.0]: https://github.com/eraxel/activerecord_callback_lens/releases/tag/v0.4.0
[0.3.0]: https://github.com/eraxel/activerecord_callback_lens/releases/tag/v0.3.0
[0.2.0]: https://github.com/eraxel/activerecord_callback_lens/releases/tag/v0.2.0
[0.1.0]: https://github.com/eraxel/activerecord_callback_lens/releases/tag/v0.1.0
