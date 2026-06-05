# Task 3: Prism-based Condition Parser

## Overview

Implement `ConditionParser`, which takes a `CallbackDefinition` with raw condition arrays and returns a new definition with `condition_tree` populated by parsing Proc/Lambda source via Prism.

## Dependency

Requires Task 1 (`ConditionTree` nodes) and Task 2 (`CallbackDefinition` with `raw_conditions`).

## Files to Create

```
lib/activerecord_callback_lens/parser/condition_parser.rb
```

## Implementation Details

### Public API

```ruby
# @param definition [Collector::CallbackDefinition]
# @return [Collector::CallbackDefinition] with condition_tree set
ConditionParser.parse(definition)
```

### Condition Assembly

1. Iterate `raw_conditions[:if]` — parse each entry, collect as `if_nodes`
2. Iterate `raw_conditions[:unless]` — parse each entry, wrap in `NotNode`, collect as `unless_nodes`
3. Combine all nodes:
   - 0 nodes → `condition_tree: nil`
   - 1 node → that node directly
   - 2+ nodes → `AndNode.new(children: all_nodes)`

### Parsing a Single Condition Entry

| Entry type | Action |
|---|---|
| `Proc` / `Lambda` | Retrieve `source_location`, parse file with Prism, locate the lambda/block node by line, walk AST |
| `Symbol` | Emit `MethodRefNode.new(name: sym.to_s, expanded_tree: nil)` |

### LambdaLocator

A Prism visitor that finds the innermost `LambdaNode` or `BlockNode` whose source range contains `target_line`. Used to isolate the condition body from the surrounding file AST.

### Recursive AST Walker

| Prism node | ConditionTree node |
|---|---|
| `Prism::AndNode` | `AndNode.new(children: [walk(left), walk(right)])` |
| `Prism::OrNode` | `OrNode.new(children: [walk(left), walk(right)])` |
| `Prism::CallNode` where `name == :!` | `NotNode.new(child: walk(receiver))` |
| `Prism::CallNode` (any other) | `PredicateNode.new(name: node.name.to_s)` |
| anything else | `nil` (ignored) |

### Error Handling

| Situation | Behavior |
|---|---|
| `source_location` is `nil` (C-level or eval'd proc) | Skip; leave `condition_tree: nil` |
| Source file does not exist | Skip; leave `condition_tree: nil` |
| Prism parse failure (syntax errors) | Warn to `$stderr`; leave `condition_tree: nil` |

## Update Entry Point

After creating `condition_parser.rb`, add the following line to `lib/activerecord_callback_lens.rb` (after the `callback_collector` require):

```ruby
require "activerecord_callback_lens/parser/condition_parser"
```

## Acceptance Criteria

- [ ] Proc condition `-> { saved_change_to_title? && status_completed? }` produces `AndNode` with two `PredicateNode` children
- [ ] `unless:` condition is wrapped in `NotNode`
- [ ] Symbol condition (`:sync_required?`) produces `MethodRefNode` with `expanded_tree: nil`
- [ ] Definitions with no conditions return `condition_tree: nil`
- [ ] Invalid source locations do not raise; a warning is printed

## Spec Reference

`docs/spec.md` — Section 4
