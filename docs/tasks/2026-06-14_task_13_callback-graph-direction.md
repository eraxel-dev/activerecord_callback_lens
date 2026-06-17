# Task 13: Change Callback Graph Direction (Left-to-Right Layout)

## Objective

Make **both** renderers use a consistent **left-to-right** direction so that conditions/predicates feed into the callback node horizontally, and separate callback chains stack vertically.

- Mermaid: `graph TD` → `graph LR`
- Graphviz: `rankdir=TB` → `rankdir=LR`

## Requirements

- The callback graph renders left-to-right across all output formats (Mermaid, Graphviz, HTML).
- Conditions/predicates appear on the left; the callback node sits on the right of each chain.
- Separate callback chains stack vertically (top to bottom) as disconnected components.

## Confirmed Decisions

| Question | Answer |
|---|---|
| Layout direction | Left to right (`graph LR` / `rankdir=LR`) |
| Callback node position | Right (conditions feed leftward into the callback) |
| Edge reversal | None needed |
| Version bump | Already at `0.6.0` — no additional bump needed |

## Files to Modify

| File | Change |
|---|---|
| `lib/activerecord_callback_lens/renderer/mermaid_renderer.rb` | `"graph TD"` → `"graph LR"`; update doc comment |
| `lib/activerecord_callback_lens/renderer/graphviz_renderer.rb` | `rankdir=TB` → `rankdir=LR`; update doc comment |
| `spec/renderer/mermaid_renderer_spec.rb` | Update `graph TD` header assertion and full-diagram fixture to `graph LR` |
| `spec/renderer/graphviz_renderer_spec.rb` | Update `rankdir=TB` assertions to `rankdir=LR` |
| `spec/renderer/html_renderer_spec.rb` | Update `graph TD` substring assertion to `graph LR` |
| `spec/cli/cli_spec.rb` | Update all `graph TD` assertions to `graph LR` |
| `spec/tasks/callback_lens_rake_spec.rb` | Update `graph TD` assertion to `graph LR` |
| `README.md` | Update direction text and embedded Mermaid example from `graph TD` to `graph LR` |
| `CHANGELOG.md` | Update `[0.6.0]` entry to document LR direction |

## Implementation Phases

### Phase 1 — MermaidRenderer direction

1. Open `lib/activerecord_callback_lens/renderer/mermaid_renderer.rb`.
2. Change `lines = ["graph TD"]` (line 37) to `lines = ["graph LR"]`.
3. Update the class doc comment (lines 6–7, 12): "top-down" → "left-to-right", `graph TD` → `graph LR`.

**Risk:** Low.

### Phase 2 — GraphvizRenderer direction

1. Open `lib/activerecord_callback_lens/renderer/graphviz_renderer.rb`.
2. Change `"  rankdir=TB;"` → `"  rankdir=LR;"`.
3. Update the class doc comment: "top-to-bottom" → "left-to-right", `rankdir=TB` → `rankdir=LR`.

**Risk:** Low.

### Phase 3 — Specs

1. `spec/renderer/mermaid_renderer_spec.rb`:
   - Header assertion: `"graph TD"` → `"graph LR"`.
   - Full-diagram heredoc: `graph TD` → `graph LR`.

2. `spec/renderer/graphviz_renderer_spec.rb`:
   - Example description and assertion: `rankdir=TB` → `rankdir=LR`.
   - Full-diagram heredoc: `rankdir=TB` → `rankdir=LR`.

3. `spec/renderer/html_renderer_spec.rb`:
   - Substring assertion: `"graph TD"` → `"graph LR"`.

4. `spec/cli/cli_spec.rb`:
   - All `graph TD` assertions → `graph LR`.

5. `spec/tasks/callback_lens_rake_spec.rb`:
   - `graph TD` assertion → `graph LR`.

**Risk:** Low (mechanical find-and-replace).

### Phase 4 — Documentation

1. `README.md`:
   - Line 36: `graph TD` → `graph LR`.
   - Embedded Mermaid example (lines 39–47): `graph TD` → `graph LR`.
   - Renderer table (line 179): update direction description.

2. `CHANGELOG.md`: update the `[0.6.0]` entry to say LR direction.

**Risk:** Low.

## Testing Strategy

- Run `bundle exec rspec` — all 240 examples must pass.
- Run RuboCop — 0 offenses.
- Optional manual check: render the Mermaid output to confirm left-to-right per-callback chains with vertical stacking of separate callbacks.

## Success Criteria

- [ ] `mermaid_renderer.rb` emits `graph LR`.
- [ ] `graphviz_renderer.rb` emits `rankdir=LR;`.
- [ ] All spec assertions updated; `bundle exec rspec` green.
- [ ] RuboCop clean.
- [ ] README example updated to `graph LR`.
- [ ] CHANGELOG `[0.6.0]` entry reflects LR direction.
