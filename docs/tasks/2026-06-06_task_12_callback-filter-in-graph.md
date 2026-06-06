# Task 12: Show Callback Method Name & Proc in Graph (v0.5.0)

## Requirements Restatement

Today, every renderer labels a callback node with only its lifecycle position
(`"#{phase}_#{event}"`, e.g. `before_validation`). This task makes each callback
node also show *what it runs* — its filter (method name or proc) — so a reader
can identify the callback without cross-referencing the source.

### Confirmed decisions

1. **Label format:** `phase_event: filter`
   (e.g. `before_validation: set_slug`).
2. **Proc rendering:**
   - Default: `(proc)`.
   - With `--expand` / `EXPAND=true`: the actual source snippet
     (e.g. `-> { compute_reading_time }`), extracted via the same
     `source_location` + Prism technique used by `ConditionParser#parse_proc`.
     Fall back to `(proc)` on any I/O or parse error.
3. **HTML consistency:** the Execution Flow and Dependency Tree sections of
   `HtmlRenderer` must also show `callback_name: filter_label` (the Callback List
   table keeps its separate Phase / Event / Filter columns).
4. **Version bump:** `0.4.1` → `0.5.0` (breaking output change).

---

## Architecture Overview

The change has two halves:

1. **Domain logic on `CallbackDefinition`** — a single source of truth for the
   callback name and the filter label, so all three renderers (and the HTML
   sections) share identical formatting and the proc-expansion logic lives in
   exactly one place.

2. **Threading the `expand` flag to the renderers.** This is the non-obvious
   part: `expand` is parsed in the CLI and rake layers but **never reaches the
   renderers today**. Their `.render` entry points take only a graph (and, for
   HTML, definitions). To honour decision 2, `expand` must be added as a keyword
   to each renderer's `.render` and threaded from the existing call sites.

### Current `expand` flow (for reference)

| Layer | Where `expand` originates | Where it currently stops |
| --- | --- | --- |
| CLI | `cli.rb:50` — `options[:expand]` passed to `build_pipeline(model_class, expand:)` | Used only to drive `MethodResolver.expand` (`cli.rb:97-99`); `render_outputs` (`cli.rb:62-66`) never sees it |
| Rake | `callback_lens_helpers.rb:97` — `expand?(ENV["EXPAND"])`; passed to `render_mermaid` / `render_graphviz` / `render_html` | Same: drives `MethodResolver.expand` only (`callback_lens_helpers.rb:40-44, 61-64, 82-86`) |
| Renderers | n/a | `MermaidRenderer.render(graph)` (`mermaid_renderer.rb:23`), `GraphvizRenderer.render(graph)` (`graphviz_renderer.rb:25`), `HtmlRenderer.render(graph, definitions:)` (`html_renderer.rb:101`) take no `expand` |

The plan extends each renderer entry point with `expand: false` and threads the
existing flag through to it, mirroring the pattern already used to thread
`expand` into `MethodResolver.expand`.

---

## Implementation Phases

### Phase 1 — `CallbackDefinition` domain methods

**Modify:** `lib/activerecord_callback_lens/collector/callback_definition.rb`

`CallbackDefinition` is currently a bare `Data.define(...)` (lines 11-19) with no
instance methods. Reopen it with a block to add behaviour:

- `#callback_name` → `"#{phase}_#{event}"` (String). Centralises the string that
  is duplicated today in `mermaid_renderer.rb:58`, `graphviz_renderer.rb:76`,
  `html_renderer.rb:159` and `html_renderer.rb:174`.
- `#filter_label(expand: false)` → String:
  - `filter` is a `Symbol` or `String` → `filter.to_s`.
  - `filter` is a `Proc`:
    - `expand == false` → `"(proc)"`.
    - `expand == true` → the proc's source snippet via a new private
      `#proc_source` helper; on **any** error → `"(proc)"`.
- Private `#proc_source` → reuses the `ConditionParser#parse_proc` technique
  (`condition_parser.rb:86-99`):
  1. `file, line = filter.source_location`; return `nil` unless `file` exists.
  2. `Prism.parse_file(file)`; return `nil` unless `result.success?`.
  3. Locate the enclosing lambda/block node by line using the existing
     `ConditionParser::LambdaLocator` (`condition_parser.rb:104-143`), capturing
     the **whole node** (not just `node.body`) and using `location.slice` (Prism)
     to return the raw `-> { ... }` / `{ ... }` text, `strip`ped to a single line
     where practical.
  4. Wrap the entire method in `rescue StandardError` (covering `Errno::ENOENT`,
     parse failures, nil `source_location`, slice errors) and return `nil`, so
     `#filter_label` falls back to `"(proc)"`.
- Add `require "prism"` and `require_relative "../parser/condition_parser"` at
  the top of `callback_definition.rb` as needed.

**Why:** a single, tested home for both the name and the label keeps the three
renderers in lockstep and isolates the only I/O-heavy logic (proc slicing) for
focused testing.

**Risk:** Medium — proc source extraction is I/O- and parse-dependent; the
`rescue → "(proc)"` fallback bounds the blast radius.

---

### Phase 2 — `MermaidRenderer`

**Modify:** `lib/activerecord_callback_lens/renderer/mermaid_renderer.rb`

- Add an `expand:` keyword to the entry point and constructor:
  - `def self.render(graph, expand: false)` → `new(graph, expand: expand).render`
    (currently line 23).
  - `def initialize(graph, expand: false)` storing `@expand` (currently line 28).
- Update `#node_label` (lines 56-64): the `Graph::CallbackNode` branch becomes
  `"#{node.definition.callback_name}: #{node.definition.filter_label(expand: @expand)}"`.
- Leave `PredicateNode` / `MethodNode` / `ConditionNode` branches unchanged.
- `#escape` (lines 72-74) already handles `"` → `&quot;`; the `:` and `->`/`{}`
  characters in proc snippets need no extra escaping for Mermaid `["..."]`
  labels, but confirm via the new spec.

**Risk:** Low.

---

### Phase 3 — `GraphvizRenderer`

**Modify:** `lib/activerecord_callback_lens/renderer/graphviz_renderer.rb`

- Add `expand:` keyword to `self.render` (line 25) and `initialize` (line 30),
  storing `@expand` — mirror Phase 2 exactly.
- Update `#node_label` (lines 74-82): `Graph::CallbackNode` branch becomes
  `"#{node.definition.callback_name}: #{node.definition.filter_label(expand: @expand)}"`.
- `#escape` (lines 90-92) escapes `"` → `\"`; verify a proc snippet containing
  `{`, `}`, `->` renders as a valid DOT label via the new spec.

**Risk:** Low.

---

### Phase 4 — `HtmlRenderer`

**Modify:** `lib/activerecord_callback_lens/renderer/html_renderer.rb`

- Add `expand:` keyword and store it:
  - `def self.render(graph, definitions:, expand: false)` (currently line 101).
  - `def initialize(graph, definitions, expand: false)` storing `@expand`
    (currently line 107).
- **Remove** the private `#filter_label(definition)` (lines 206-209) and delegate
  to the domain method: every call site uses
  `definition.filter_label(expand: @expand)`.
  - Callback List table cell (line 141): `escape(definition.filter_label(expand: @expand))`.
- **Execution Flow** (`#execution_flow`, lines 157-166): change the list item
  from `escape("#{d.phase}_#{d.event}")` (line 159) to
  `escape("#{d.callback_name}: #{d.filter_label(expand: @expand)}")`.
- **Dependency Tree** (`#dependency_trees`, lines 170-183): change the `<li>`
  header from `escape("#{definition.phase}_#{definition.event}")` (line 174) to
  `escape("#{definition.callback_name}: #{definition.filter_label(expand: @expand)}")`.
- **Pass `expand` to the embedded diagrams** so the HTML report's Mermaid /
  Graphviz sections match the page text:
  - `#mermaid_section` (line 189): `MermaidRenderer.render(@graph, expand: @expand)`.
  - `#svg_section` (line 196): `GraphvizRenderer.new(@graph, expand: @expand).to_svg`.

**Why:** decision 3 requires Execution Flow and Dependency Tree to show
`callback_name: filter_label`; delegating to the domain method removes the now
duplicate private helper.

**Risk:** Low–Medium (multiple call sites; covered by Phase 6 specs).

---

### Phase 5 — Thread `expand` through CLI and Rake

**Modify:** `lib/activerecord_callback_lens/cli/cli.rb`

- `#render_outputs` (lines 62-66) does not currently receive `expand`. Thread it:
  - In `#analyze` (line 51): `render_outputs(graph, definitions, expand: options[:expand])`.
  - Update `#render_outputs(graph, definitions, expand:)` to pass it on:
    - `Renderer::MermaidRenderer.render(graph, expand: expand)` (line 63).
    - `Renderer::GraphvizRenderer.render(graph, expand: expand)` (line 64).
    - `write_html(graph, definitions, options[:html], expand: expand)` (line 65).
  - Update `#write_html` (lines 109-113) to accept `expand:` and call
    `Renderer::HtmlRenderer.render(graph, definitions: definitions, expand: expand)`.

**Modify:** `lib/activerecord_callback_lens/tasks/callback_lens_helpers.rb`

- The helpers already receive `expand:` (lines 37, 57, 79) and compute it via
  `expand?` (lines 97-99). Pass it into the renderers:
  - `render_mermaid` (line 46): `MermaidRenderer.render(graph, expand: expand)`.
  - `render_graphviz` (line 66): `GraphvizRenderer.render(graph, expand: expand)`.
  - `render_html` (line 88): `HtmlRenderer.render(graph, definitions: definitions, expand: expand)`.

No change needed to `callback_lens.rake` — it already passes `expand:` into the
helpers (lines 11, 18, 26, 35).

**Risk:** Low — purely additive keyword threading; default `expand: false`
preserves behaviour for any caller that omits it.

---

### Phase 6 — Specs

**Modify:** `spec/collector/callback_definition_spec.rb`

- `#callback_name` returns `"before_save"` for `phase: :before, event: :save`.
- `#filter_label(expand: false)` for a `Symbol` filter → `"set_slug"`.
- `#filter_label(expand: false)` for a `String` filter → that string.
- `#filter_label(expand: false)` for a `Proc` filter → `"(proc)"`.
- `#filter_label(expand: true)` for a real lambda defined in a fixture file →
  the source snippet (e.g. `-> { compute_reading_time }`).
- `#filter_label(expand: true)` when `source_location` is nil / file missing /
  unparseable → falls back to `"(proc)"` (exercise the `rescue`).

**Modify:** `spec/renderer/mermaid_renderer_spec.rb`

- Update the existing "renders a CallbackNode label as phase_event" expectation
  (lines 25-29): the helper's `filter: :placeholder` (line 12) means the label
  is now `before_save: placeholder` → expect `%(  n0["before_save: placeholder"])`.
- Add a case: `expand: true` with a proc filter renders the snippet in the label.
- Add a case: `expand: false` (default) with a proc filter renders
  `before_save: (proc)`.

**Modify:** `spec/renderer/graphviz_renderer_spec.rb`

- Mirror the Mermaid updates: default symbol label is now
  `before_save: placeholder`; add proc default (`(proc)`) and `expand: true`
  (snippet) cases; verify DOT escaping of `{`/`}`/`->`.

**Modify:** `spec/renderer/html_renderer_spec.rb`

- Update Execution Flow expectation to `callback_name: filter_label`.
- Update Dependency Tree `<li>` header expectation to `callback_name: filter_label`.
- Add an `expand: true` case asserting the proc snippet appears in the table,
  execution flow, and dependency tree, and that the embedded Mermaid section
  reflects `expand`.
- Confirm the Callback List table still shows the filter in its own column.

**Modify (if assertions reference the old label):**
`spec/cli/cli_spec.rb`, `spec/tasks/callback_lens_rake_spec.rb` — update any
expectation that matches a bare `phase_event` callback label; add a smoke test
that `--expand` / `EXPAND=true` produces proc snippets in stdout output.

**Risk:** Low — mechanical, but the spec fixtures for `expand: true` need a
real proc with a resolvable `source_location` (define a small lambda in a
fixture file under `spec/`).

---

### Phase 7 — Version bump & changelog

**Modify:** `lib/activerecord_callback_lens/version.rb`

- `VERSION = "0.4.1"` → `VERSION = "0.5.0"` (line 4).

**Modify:** `CHANGELOG.md`

- Add a `## [0.5.0] - 2026-06-06` entry above `## [0.4.1]` with:
  - **Changed (breaking):** Callback graph nodes now label each callback as
    `phase_event: filter` (e.g. `before_validation: set_slug`) across the
    Mermaid, Graphviz, and HTML renderers, replacing the previous
    `phase_event`-only label.
  - **Added:** `CallbackDefinition#callback_name` and
    `#filter_label(expand:)`; with `--expand` / `EXPAND=true`, proc filters
    render their actual source snippet (falling back to `(proc)` on error).
  - **Changed:** `MermaidRenderer.render`, `GraphvizRenderer.render`, and
    `HtmlRenderer.render` now accept an `expand:` keyword; the CLI and Rake
    layers thread the existing `--expand` / `EXPAND` flag through to them.

**Risk:** Low.

---

## Testing Strategy

- **Unit:** `CallbackDefinition` (`#callback_name`, `#filter_label` for symbol /
  string / proc, expand on/off, error fallback); each renderer's `#node_label`
  via its `.render` output for both `expand` modes.
- **Integration:** `HtmlRenderer` end-to-end for the three sections + embedded
  diagrams; CLI `analyze` and rake tasks with and without `--expand` /
  `EXPAND=true`.
- **Edge cases:** proc with nil `source_location`; proc in a missing /
  unparseable file; label characters (`:`, `{`, `}`, `->`, `"`) escaped per
  renderer.

---

## Risks & Mitigations

- **Risk:** Proc source extraction fails or is slow (file I/O + Prism parse).
  - Mitigation: single `rescue StandardError → nil → "(proc)"` fallback; only
    runs when `expand: true`.
- **Risk:** `expand` threading missed at one call site, so a renderer silently
  ignores `--expand`.
  - Mitigation: explicit table of call sites (Phase 5) and CLI/rake smoke tests
    in Phase 6.
- **Risk:** Label format change breaks downstream consumers parsing the old
  `phase_event` labels.
  - Mitigation: documented as a breaking change under the `0.5.0` minor bump and
    in the changelog.

## Complexity Estimate

**Low–Medium.** Phases 1–3 and 7 are straightforward. Phase 5 (threading `expand`
through the CLI and rake call sites) and Phase 6 (updating many spec assertions)
require careful, complete changes but no design decisions.

---

## Success Criteria

- [ ] `CallbackDefinition#callback_name` returns `"#{phase}_#{event}"`.
- [ ] `CallbackDefinition#filter_label(expand: false)` returns the symbol/string
      name, or `"(proc)"` for procs.
- [ ] `CallbackDefinition#filter_label(expand: true)` returns the proc source
      snippet, falling back to `"(proc)"` on any error.
- [ ] Mermaid, Graphviz, and HTML callback nodes show `phase_event: filter`.
- [ ] HTML Execution Flow and Dependency Tree show `callback_name: filter_label`.
- [ ] `--expand` (CLI) and `EXPAND=true` (Rake) flow through to all renderers,
      including HTML's embedded Mermaid/Graphviz.
- [ ] Version is `0.5.0` with a matching `[0.5.0]` changelog entry.
- [ ] All existing and new specs pass; Rubocop is clean.
