# Task 7: Expose `--expand` (CLI) and `EXPAND` (Rake) + v0.2 Docs

## Overview

Wire the expansion pipeline into both user-facing interfaces (Thor CLI and
Rake tasks), add the top-level `require` for the resolver, and update the
version, README, and CHANGELOG for the v0.2 release.

> **Note:** Neither `--expand` nor `EXPAND` exist in the current code, despite
> the spec suggesting partial stubs — this task adds them from scratch.

## Dependency

Requires Tasks 5 & 6 (`MethodResolver.resolve` and `.expand` complete).

## Files to Modify

```
lib/activerecord_callback_lens.rb                            # add resolver require
lib/activerecord_callback_lens/version.rb                    # bump to 0.2.0
lib/activerecord_callback_lens/cli/cli.rb                    # add --expand option
lib/activerecord_callback_lens/tasks/callback_lens.rake      # add EXPAND support
README.md                                                    # document --expand / EXPAND
CHANGELOG.md                                                 # add v0.2 entry
spec/cli/cli_spec.rb                                         # extend with expand tests
spec/tasks/callback_lens_rake_spec.rb                        # extend with expand tests
```

---

## Deliverables

### 1. Top-level require

Add to `lib/activerecord_callback_lens.rb`:

```ruby
require "activerecord_callback_lens/resolver/method_resolver"
```

### 2. Version bump

```ruby
# lib/activerecord_callback_lens/version.rb
VERSION = "0.2.0"
```

### 3. CLI — `--expand` flag

Add to the `analyze` command in `lib/activerecord_callback_lens/cli/cli.rb`:

```ruby
option :expand, type: :boolean, default: false,
                desc: "Expand method conditions recursively (up to depth 5)"
```

In the `analyze` method body, after parsing definitions, apply expansion when
the flag is set:

```ruby
if options[:expand]
  definitions = definitions.map do |d|
    Resolver::MethodResolver.expand(d, model_class)
  end
end
```

Keep existing options (`--mermaid`, `--graphviz`, `--html`) unchanged.

### 4. Rake — `EXPAND` env var

In `lib/activerecord_callback_lens/tasks/callback_lens.rake`, update the
shared `pipeline` helper to read `ENV["EXPAND"]`:

```ruby
def pipeline(model_class)
  definitions = Collector::CallbackCollector.collect(model_class)
  definitions = definitions.map { |d| Parser::ConditionParser.parse(d) }
  if ENV["EXPAND"].to_s.strip.downcase == "true"
    definitions = definitions.map do |d|
      Resolver::MethodResolver.expand(d, model_class)
    end
  end
  definitions
end
```

Apply this `pipeline` consistently across all rake tasks (`analyze`,
`mermaid`, `graphviz`, `html`).

**Truthy parsing rule:** only the string `"true"` (case-insensitive, stripped)
enables expansion. Any other value (`"1"`, `"yes"`, empty, absent) leaves
expansion off. Test this explicitly.

### 5. README usage section

Add a new subsection under CLI and Rake usage:

```markdown
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
rake callback_lens:html    MODEL=User EXPAND=true OUT=tmp/user_expanded.html
```
```

### 6. CHANGELOG entry

Prepend to `CHANGELOG.md`:

```markdown
## [0.2.0] - 2026-06-05

### Added
- `MethodResolver`: recursively expand symbol callback conditions into
  `ConditionTree` sub-trees (up to `MAX_DEPTH = 5` levels).
- Cycle detection via a `visited` set; cyclic `MethodRefNode`s are left with
  `expanded_tree: nil`.
- `--expand` flag for the `analyze` CLI command.
- `EXPAND=true` environment variable for all Rake tasks.
```

---

## Acceptance Criteria

- `callback_lens analyze SomeModel --expand --mermaid` outputs a Mermaid
  diagram that includes nodes for expanded method bodies; without `--expand`
  the output matches v0.1.
- `rake callback_lens:analyze MODEL=SomeModel EXPAND=true` produces the same
  expanded output; `EXPAND` absent or `EXPAND=false` preserves v0.1 behaviour.
- `EXPAND=1` and `EXPAND=yes` do NOT enable expansion (only `"true"` does).
- All existing CLI and Rake specs remain green.
- The gem loads without error (`require "activerecord_callback_lens"` includes
  the resolver).
- Version is `0.2.0`; CHANGELOG and README are updated.

---

## Specs

### `spec/cli/cli_spec.rb` additions

| Scenario | Assertion |
|---|---|
| `analyze Model --expand --mermaid` | Mermaid output includes expanded method node |
| `analyze Model --mermaid` (no expand) | Output unchanged from v0.1 baseline |
| `MethodResolver.expand` called only with `--expand` | Verify via spy/mock |

### `spec/tasks/callback_lens_rake_spec.rb` additions

| Scenario | Assertion |
|---|---|
| `EXPAND=true rake callback_lens:analyze` | Expansion applied |
| `EXPAND=false rake callback_lens:analyze` | No expansion |
| `EXPAND=1 rake callback_lens:analyze` | No expansion (explicit truthy-parse test) |
| `EXPAND=` (empty) | No expansion |

---

## Risks

- **Low:** Truthy parsing of `EXPAND` must be explicit — test all edge cases
  (`"1"`, `"yes"`, `""`, `nil`) to avoid silent misinterpretation.
- **Low:** Ensure the `pipeline` helper is used consistently across *all* rake
  tasks so the expansion flag applies uniformly.
- **Low:** Keep the no-expand path byte-for-byte identical to v0.1 output;
  any accidental structural change will break existing specs.
