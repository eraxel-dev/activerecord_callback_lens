# Task 10: v0.4 — HtmlRenderer with Embedded Mermaid and SVG

## Requirements Restatement

v0.4 adds `HtmlRenderer`, which produces a self-contained HTML report for a model's callbacks. Per `docs/spec.md` sections 7, 8.3, 10.2, 11.2, this includes:

1. **`ExecutionOrderAnalyzer`** — sorts `CallbackDefinition` arrays by the canonical Rails execution order (create or update path).
2. **`HtmlRenderer`** — generates a single self-contained HTML file with five sections:
   - Callback List (table: Phase, Event, Filter, Conditions)
   - Execution Flow (ordered list from `ExecutionOrderAnalyzer`)
   - Dependency Tree (nested `<ul>` built from each definition's `ConditionTree`)
   - Mermaid Diagram (`<pre class="mermaid">` block via CDN)
   - Graphviz SVG (inline `<svg>` if `dot` is available; section omitted otherwise)
3. **CLI update** — `analyze` gains `--html FILE` option that writes the HTML report to a file path.
4. **Rake task update** — new `callback_lens:html` task with `MODEL`, `OUT` (default: `callback_lens_report.html`), and `EXPAND` env vars.
5. **Version bump** to `0.4.0`.
6. **Unit tests** for all new and modified components.

---

## Implementation Phases

### Phase 1 — `ExecutionOrderAnalyzer`

**New file:** `lib/activerecord_callback_lens/execution_order_analyzer.rb`

- Implement `ExecutionOrderAnalyzer` class with:
  - `SAVE_ORDER` and `UPDATE_ORDER` constants (from spec section 7.2)
  - `.sort(definitions, operation: :create)` class method that sorts by canonical callback position, placing unrecognised callbacks at the end (index 999)
- Add `require` in `lib/activerecord_callback_lens.rb`

### Phase 2 — `HtmlRenderer`

**New file:** `lib/activerecord_callback_lens/renderer/html_renderer.rb`

- Implement `HtmlRenderer` class with:
  - `.render(graph, definitions:)` class method entry point
  - `#render` — assembles the full HTML document (spec section 8.3 template)
  - `#callback_table` — `<table>` with columns Phase, Event, Filter, Conditions; one row per definition
  - `#execution_flow` — `<ol>` of callbacks sorted by `ExecutionOrderAnalyzer` (`:create` path)
  - `#dependency_trees` — iterates definitions with a `condition_tree`, renders each as a nested `<ul>` via a recursive `#tree_to_html(node)` helper that handles `AndNode`, `OrNode`, `NotNode`, `PredicateNode`, `MethodRefNode`
  - `#mermaid_section` — `<pre class="mermaid">` block populated by `MermaidRenderer`
  - `#svg_section` — calls `GraphvizRenderer#to_svg`; wraps result in a `<div>` or returns empty string if `nil`
  - `MERMAID_CDN` constant (`"https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"`)
- Add `require` in `lib/activerecord_callback_lens.rb`

### Phase 3 — CLI update

**Modify:** `lib/activerecord_callback_lens/cli/cli.rb`

- Add `option :html, type: :string, desc: "Write HTML report to FILE"` to the `analyze` command
- Add `require_relative "../renderer/html_renderer"` at the top
- In `#analyze`: when `options[:html]` is present, call `HtmlRenderer.render(graph, definitions: definitions)` and `File.write(path, html)`, then print confirmation to stdout
- Refactor `#build_graph` into `#build_pipeline` that returns `[definitions, graph]` so both are accessible at render time

### Phase 4 — Rake task update

**Modify:** `lib/activerecord_callback_lens/tasks/callback_lens.rake`

- Add `html` task delegating to `CallbackLensRakeHelpers.render_html`
- `OUT` env var with default `callback_lens_report.html`
- Print `"Report written to #{out}"` on success

**Modify:** `lib/activerecord_callback_lens/tasks/callback_lens_helpers.rb`

- Add `render_html(model_class, expand: false)` method that runs the full pipeline and returns `HtmlRenderer.render(graph, definitions: definitions)`

### Phase 5 — Version bump

**Modify:** `lib/activerecord_callback_lens/version.rb`
- Change `VERSION = "0.3.0"` to `VERSION = "0.4.0"`

### Phase 6 — Unit tests

**New files:**

- `spec/execution_order_analyzer_spec.rb`
  - `.sort` returns definitions in the canonical create-path order
  - `.sort` returns definitions in the canonical update-path order when `operation: :update`
  - Unrecognised callback types are sorted to the end (index 999)
  - Preserves relative order of definitions at the same canonical position

- `spec/renderer/html_renderer_spec.rb`
  - Output starts with `<!DOCTYPE html>` and includes `<title>`
  - Callback table contains Phase, Event, Filter column headers
  - Execution flow section is present
  - Mermaid CDN `<script>` tag is present
  - `<pre class="mermaid">` block contains Mermaid diagram output
  - SVG section is present when `GraphvizRenderer#to_svg` returns an SVG string (stubbed)
  - SVG section is absent when `GraphvizRenderer#to_svg` returns `nil`
  - Dependency tree `<ul>` is rendered for definitions that have a `condition_tree`

**Modify:**

- `spec/cli/cli_spec.rb` — add `describe "analyze --html"` block:
  - Writes an HTML file to a tmp path
  - Prints `"HTML report written to"` message to stdout
  - File content starts with `<!DOCTYPE html>`
  - Does not write a file when `--html` is absent

- `spec/tasks/callback_lens_rake_spec.rb` — add `describe ".render_html"` block:
  - Returns a string starting with `<!DOCTYPE html>`
  - Contains callback names from the model
  - Passes `expand: true` flag through to the pipeline (MethodResolver is called)
  - `expand: false` by default (MethodResolver is not called)

---

## Deliverables

| File | Action |
|---|---|
| `lib/activerecord_callback_lens/execution_order_analyzer.rb` | Create |
| `lib/activerecord_callback_lens/renderer/html_renderer.rb` | Create |
| `spec/execution_order_analyzer_spec.rb` | Create |
| `spec/renderer/html_renderer_spec.rb` | Create |
| `lib/activerecord_callback_lens.rb` | Modify — add requires |
| `lib/activerecord_callback_lens/version.rb` | Modify — bump to 0.4.0 |
| `lib/activerecord_callback_lens/cli/cli.rb` | Modify — `--html` option, `#build_pipeline` refactor |
| `lib/activerecord_callback_lens/tasks/callback_lens.rake` | Modify — add `html` task |
| `lib/activerecord_callback_lens/tasks/callback_lens_helpers.rb` | Modify — add `render_html` |
| `spec/cli/cli_spec.rb` | Modify — add `--html` tests |
| `spec/tasks/callback_lens_rake_spec.rb` | Modify — add `render_html` tests |

---

## Risks

- **MEDIUM: `dot` binary availability in CI** — `to_svg` already returns `nil` gracefully; tests must stub `GraphvizRenderer#to_svg` to avoid a hard CI dependency on Graphviz.
- **LOW: `File.write` in CLI tests** — use `Dir.mktmpdir` / `Tempfile` to avoid leaving artifacts; clean up in `after`.
- **LOW: HTML escaping** — filter names and predicate names containing `<`, `>`, or `&` must be HTML-escaped; use `CGI.escapeHTML`.
- **LOW: `definitions` not available post-`#build_graph`** — the current private `#build_graph` method discards definitions; refactor into `#build_pipeline` returning `[definitions, graph]`.

---

## Estimated Complexity: LOW-MEDIUM

| Area | Estimate |
|---|---|
| `ExecutionOrderAnalyzer` | 30 min |
| `HtmlRenderer` | 2–3 hours |
| CLI + rake + helpers update | 1 hour |
| Tests | 2 hours |
| **Total** | **~5–6 hours** |
