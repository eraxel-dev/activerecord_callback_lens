# Task 9: GraphvizRenderer CLI & Rake Integration

## Overview

Wire `GraphvizRenderer` into the user-facing interfaces: add a `--graphviz`
flag to the CLI `analyze` command and a `callback_lens:graphviz` Rake task.
Also update the version to 0.3.0 and record the release in CHANGELOG and README.

## Dependency

Requires Task 8 (`GraphvizRenderer` complete and required from the top-level
entry point).

## Files to Modify

```
lib/activerecord_callback_lens/version.rb                    # bump to 0.3.0
lib/activerecord_callback_lens/cli/cli.rb                    # add --graphviz option
lib/activerecord_callback_lens/tasks/callback_lens_helpers.rb # add render_graphviz
lib/activerecord_callback_lens/tasks/callback_lens.rake      # add graphviz task
CHANGELOG.md                                                 # add v0.3 entry
README.md                                                    # document --graphviz / graphviz task
spec/cli/cli_spec.rb                                         # add --graphviz scenarios
spec/tasks/callback_lens_rake_spec.rb                        # add graphviz task scenarios
```

---

## Deliverables

### 1. Version bump

```ruby
# lib/activerecord_callback_lens/version.rb
VERSION = "0.3.0"
```

### 2. CLI — `--graphviz` flag

Add one option to the existing `analyze` command in
`lib/activerecord_callback_lens/cli/cli.rb`:

```ruby
option :graphviz, type: :boolean, default: false,
                  desc: "Output DOT graph via Graphviz to stdout"
```

Add the require at the top of the file:

```ruby
require_relative "../renderer/graphviz_renderer"
```

In the `analyze` method body, after the existing Mermaid output line:

```ruby
puts Renderer::GraphvizRenderer.render(graph) if options[:graphviz]
```

The `--mermaid` and `--graphviz` options are independent and may be combined.

### 3. Rake helper — `render_graphviz`

Add to `lib/activerecord_callback_lens/tasks/callback_lens_helpers.rb`:

```ruby
# @param model_class [Class]
# @param expand [Boolean]
# @return [String] DOT language string
def render_graphviz(model_class, expand: false)
  definitions = ActiverecordCallbackLens::Collector::CallbackCollector.collect(model_class)
  definitions = definitions.map { |d| ActiverecordCallbackLens::Parser::ConditionParser.parse(d) }
  if expand
    definitions = definitions.map do |d|
      ActiverecordCallbackLens::Resolver::MethodResolver.expand(d, model_class)
    end
  end
  graph = ActiverecordCallbackLens::Graph::GraphBuilder.build(definitions)
  ActiverecordCallbackLens::Renderer::GraphvizRenderer.render(graph)
end
```

### 4. Rake task — `callback_lens:graphviz`

Add inside the existing `callback_lens` namespace in
`lib/activerecord_callback_lens/tasks/callback_lens.rake`:

```rake
desc "Write Graphviz DOT to STDOUT for MODEL " \
     "(e.g. rake callback_lens:graphviz MODEL=User EXPAND=true)"
task graphviz: :environment do
  model_class = CallbackLensRakeHelpers.resolve_model!(ENV.fetch("MODEL", nil))
  expand = CallbackLensRakeHelpers.expand?(ENV.fetch("EXPAND", nil))
  puts CallbackLensRakeHelpers.render_graphviz(model_class, expand: expand)
end
```

### 5. CHANGELOG entry

Prepend to `CHANGELOG.md`:

```markdown
## [0.3.0] - 2026-06-06

### Added
- `GraphvizRenderer`: converts a `Graph::Graph` to a DOT language string.
- `GraphvizRenderer#to_svg`: shells out to the `dot` binary and returns an SVG
  string; returns `nil` when Graphviz is not installed.
- `--graphviz` flag for the `analyze` CLI command (outputs DOT to stdout).
- `callback_lens:graphviz` Rake task (outputs DOT to stdout).
```

### 6. README usage section

Add a new subsection under the CLI and Rake usage sections:

```markdown
#### Graphviz DOT output

Pass `--graphviz` (CLI) or use `callback_lens:graphviz` (Rake) to output a
[Graphviz DOT](https://graphviz.org/) diagram to stdout. Pipe it to `dot` to
generate an image:

```bash
# CLI — print DOT to stdout
callback_lens analyze User --graphviz

# CLI — combine with Mermaid output
callback_lens analyze User --mermaid --graphviz

# CLI — pipe to dot for a PNG
callback_lens analyze User --graphviz | dot -Tpng -o callbacks.png

# Rake
rake callback_lens:graphviz MODEL=User
rake callback_lens:graphviz MODEL=User EXPAND=true
```

Requires [Graphviz](https://graphviz.org/download/) only when piping to `dot`.
```

---

## Acceptance Criteria

- `callback_lens analyze SomeModel --graphviz` prints a DOT string starting
  with `digraph callback_lens {` to stdout.
- `--mermaid` and `--graphviz` may be combined; both outputs appear in stdout.
- Without `--graphviz`, no DOT output is printed (existing behaviour unchanged).
- `rake callback_lens:graphviz MODEL=SomeModel` prints the same DOT output.
- `rake callback_lens:graphviz MODEL=SomeModel EXPAND=true` applies method
  expansion before rendering.
- Missing `MODEL` raises the same descriptive error as the other Rake tasks.
- All existing CLI and Rake specs remain green.
- Version is `0.3.0`; CHANGELOG and README are updated.

---

## Specs

### `spec/cli/cli_spec.rb` additions

| Scenario | Assertion |
|---|---|
| `analyze Model --graphviz` | Output starts with `digraph callback_lens {` |
| `analyze Model --graphviz` | Output ends with `}` |
| `analyze Model --mermaid --graphviz` | Output contains both `graph TD` and `digraph callback_lens {` |
| `analyze Model` (no flags) | No `digraph` in output |

### `spec/tasks/callback_lens_rake_spec.rb` additions

| Scenario | Assertion |
|---|---|
| `callback_lens:graphviz` with valid MODEL | Output starts with `digraph callback_lens {` |
| `callback_lens:graphviz` with `EXPAND=true` | `MethodResolver.expand` is called |
| `callback_lens:graphviz` without MODEL | Raises descriptive error |

---

## Risks

- **Low:** The `render_graphviz` helper duplicates the pipeline logic from
  `render_mermaid`. Acceptable for now; shared extraction is a v0.4 concern.
- **Low:** Ensure the `--graphviz` option default is `false` so existing
  invocations without the flag are byte-for-byte identical to v0.2 output.
