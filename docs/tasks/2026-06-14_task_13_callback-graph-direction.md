# Task 13: Change Callback Graph Direction (Top-to-Bottom Layout)

## Objective

Make **both** renderers use a consistent **top-to-bottom** direction so that conditions/predicates flow downward into the callback node.

- Mermaid already uses `graph TD` — no change required.
- Graphviz currently uses `rankdir=LR` (left-to-right) — change to `rankdir=TB` (top-to-bottom).

## Requirements

- The callback graph renders top-to-bottom across all output formats (Mermaid, Graphviz, HTML).
- Conditions/predicates appear above the callback node; the callback node sits at the bottom of each chain.
- Separate callback chains stack naturally in both renderers.

## Confirmed Decisions

| Question | Answer |
|---|---|
| Layout direction | Top to bottom (`graph TD` / `rankdir=TB`) |
| Callback node position | Bottom (conditions feed downward into the callback) |
| Edge reversal | None needed |
| Version bump | Yes — `0.5.0` → `0.6.0` |

## Files to Modify

| File | Change |
|---|---|
| `lib/activerecord_callback_lens/renderer/graphviz_renderer.rb` | `rankdir=LR` → `rankdir=TB`; update doc comment |
| `spec/renderer/graphviz_renderer_spec.rb` | Update 3 occurrences of `rankdir=LR` → `rankdir=TB` |
| `lib/activerecord_callback_lens/version.rb` | `"0.5.0"` → `"0.6.0"` |
| `CHANGELOG.md` | Add `[0.6.0]` entry |

### No-change files (already top-to-bottom)

- `lib/activerecord_callback_lens/renderer/mermaid_renderer.rb` — already `graph TD`
- `spec/renderer/mermaid_renderer_spec.rb` — already asserts `graph TD`
- `spec/renderer/html_renderer_spec.rb` — already asserts `graph TD`
- `spec/cli/cli_spec.rb` — already asserts `graph TD`
- `spec/tasks/callback_lens_rake_spec.rb` — already asserts `graph TD`
- `README.md` — already documents `graph TD`

## Implementation Phases

### Phase 1 — GraphvizRenderer direction

1. Open `lib/activerecord_callback_lens/renderer/graphviz_renderer.rb`.
2. Change the class doc comment: "left-to-right rank direction" → "top-to-bottom rank direction", and `rankdir=LR` → `rankdir=TB` in the example block.
3. In `#render`: change `"  rankdir=LR;"` → `"  rankdir=TB;"` (line 39).

**Risk:** Low.

### Phase 2 — Graphviz specs

Update `spec/renderer/graphviz_renderer_spec.rb`:

- Line 29: rename the example description from `rankdir=LR` to `rankdir=TB`.
- Line 31: `eq("  rankdir=LR;")` → `eq("  rankdir=TB;")`.
- Line 89 (full-diagram fixture): `rankdir=LR;` → `rankdir=TB;`.

**Risk:** Low.

### Phase 3 — Version bump and changelog

1. `lib/activerecord_callback_lens/version.rb`: `"0.5.0"` → `"0.6.0"`.
2. `CHANGELOG.md`: add `## [0.6.0]` section noting that Graphviz output changed from `rankdir=LR` to `rankdir=TB` (breaking output change for consumers parsing raw DOT text).

**Risk:** Low.

## Testing Strategy

- Run `bundle exec rspec` — all specs must pass.
- Run Rubocop — must be clean.
- Optional manual check: run `dot -Tsvg` on sample output to confirm top-to-bottom rendering.

## Success Criteria

- [ ] `graphviz_renderer.rb` emits `rankdir=TB;`.
- [ ] Graphviz spec assertions updated; `bundle exec rspec` green.
- [ ] Rubocop clean.
- [ ] Version bumped to `0.6.0` with CHANGELOG entry.
