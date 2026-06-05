# Task 6: Expansion Pipeline — Populate `MethodRefNode#expanded_tree` per Definition

## Overview

Provide a per-definition expansion entry point (`MethodResolver.expand`) that
walks a `CallbackDefinition`'s `condition_tree`, finds every `MethodRefNode`,
resolves it with `MethodResolver.resolve`, and rebuilds the tree with
populated `expanded_tree` fields. This bridges the resolver core (Task 5) and
the CLI/Rake integration (Task 7).

## Dependency

Requires Task 5 (`MethodResolver.resolve` complete).

## Files to Modify

```
lib/activerecord_callback_lens/resolver/method_resolver.rb   # add .expand class method
spec/resolver/method_resolver_spec.rb                        # add expansion helper specs
```

No changes to `GraphBuilder` — it already recurses into `expanded_tree` when
present. Verify this and document it in a comment.

---

## Deliverables

### 1. `MethodResolver.expand` — per-definition helper

```ruby
# @param definition [Collector::CallbackDefinition]
# @param model_class [Class]
# @return [Collector::CallbackDefinition] with condition_tree fully expanded
def self.expand(definition, model_class)
  new(model_class).expand(definition)
end

def expand(definition)
  return definition unless definition.condition_tree

  expanded = expand_tree(definition.condition_tree)
  definition.with(condition_tree: expanded)
end
```

### 2. `expand_tree` — recursive tree rebuild

Walk the `condition_tree` and for each `MethodRefNode`, call
`resolve(node.name.to_sym)` and rebuild with `.with(expanded_tree: result)`.
Recurse into `AndNode#children`, `OrNode#children`, and `NotNode#child`
to ensure deep expansion.

```ruby
def expand_tree(node)
  case node
  in Parser::ConditionTree::AndNode
    node.with(children: node.children.map { |c| expand_tree(c) })
  in Parser::ConditionTree::OrNode
    node.with(children: node.children.map { |c| expand_tree(c) })
  in Parser::ConditionTree::NotNode
    node.with(child: expand_tree(node.child))
  in Parser::ConditionTree::MethodRefNode
    sub = resolve(node.name.to_sym)
    node.with(expanded_tree: sub)
  else
    node
  end
end
```

### 3. Verify `GraphBuilder` compatibility

Confirm that `GraphBuilder#add_tree` already handles `MethodRefNode` with
a populated `expanded_tree` by recursing via:

```ruby
in ConditionTree::MethodRefNode => n
  # ...
  add_tree(n.expanded_tree, parent_id: m.id) if n.expanded_tree
```

No changes to `GraphBuilder` are needed. Add a comment in the source noting
that `expanded_tree` is populated upstream by `MethodResolver.expand`.

---

## Acceptance Criteria

- Given a model whose callback condition is a symbol method that itself
  composes predicates and method refs, `MethodResolver.expand(definition, Model)`
  returns a definition whose `condition_tree` contains populated `expanded_tree`
  fields on all `MethodRefNode`s reachable within `MAX_DEPTH`.
- Passing a definition with no `condition_tree` (nil) returns the definition
  unchanged.
- When called with a definition whose `condition_tree` contains no
  `MethodRefNode`s, the tree is returned unchanged.
- `GraphBuilder.build` over expanded definitions produces additional
  `MethodNode` + edge structure for the expanded sub-trees (verified via
  `MermaidRenderer` output containing the expanded method names).
- The non-expansion path (definitions that have NOT been passed through
  `expand`) produces output byte-for-byte identical to v0.1 — existing
  graph/mermaid specs stay green.

---

## Specs (additions to `spec/resolver/method_resolver_spec.rb`)

| Scenario | Expected result |
|---|---|
| Definition with `nil` condition_tree | Returns definition unchanged |
| Definition with no `MethodRefNode` | Tree returned unchanged |
| Definition with one `MethodRefNode` | Node's `expanded_tree` populated |
| Definition with nested `MethodRefNode` inside `AndNode` | All refs expanded |
| Definition passed to `GraphBuilder` after expansion | Mermaid output includes expanded method name |

---

## Risks

- **Low/Medium:** Deciding where the tree-walk-and-rebuild lives. Keep it in
  `MethodResolver` to centralise all `MethodRefNode` handling.
- **Low:** `MethodRefNode#name` is a `String`; always convert to `Symbol`
  before calling `resolve`.
- **Low:** `Data#with` creates a new object; ensure the recursive rebuild
  returns the rebuilt node at every level (avoid mutating callers'
  references).
