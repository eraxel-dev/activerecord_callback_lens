# Task 5: MethodResolver Core — Recursive Expansion & Cycle Detection

## Overview

Implement `lib/activerecord_callback_lens/resolver/method_resolver.rb`.
Given a `MethodRefNode` symbol name (e.g. `:sync_required?`), locate the
method definition on the model class, parse its body into a `ConditionTree`,
and recursively expand any nested `MethodRefNode`s — guarding against infinite
recursion via a `visited` set and `MAX_DEPTH` cap.

## Dependency

Requires Tasks 1–4 (data models, collector, condition parser, and graph/renderer pipeline all complete).

## Files to Create / Modify

```
lib/activerecord_callback_lens/resolver/method_resolver.rb   # new
spec/resolver/method_resolver_spec.rb                        # new
```

If the boolean-AST walker in `ConditionParser#walk` is private/duplicated,
extract it into a shared location (e.g. `Parser::AstWalker`) and update
`ConditionParser` to delegate to it — keeping its public API and existing
specs green.

---

## Deliverables

### 1. `MethodResolver` class

```ruby
module ActiverecordCallbackLens
  module Resolver
    class MethodResolver
      MAX_DEPTH = 5

      # @param model_class [Class]
      # @param method_name [Symbol]
      # @return [Parser::ConditionTree::Node | nil]
      def self.resolve(model_class, method_name)
        new(model_class).resolve(method_name)
      end

      def initialize(model_class)
        @model_class = model_class
      end

      def resolve(method_name, depth: 0, visited: Set.new)
        return nil if depth >= MAX_DEPTH
        return nil if visited.include?(method_name)

        visited.add(method_name)
        node = locate_and_parse(method_name)
        expand_refs(node, depth: depth + 1, visited: visited)
      end
    end
  end
end
```

### 2. Method location strategy (`locate_and_parse`)

1. Call `@model_class.instance_method(method_name).source_location` → `[file, line]`.
2. Return `nil` if `source_location` is `nil` (C-level or eval'd methods).
3. Parse the file with `Prism.parse_file(file)`. On failure, warn to `$stderr` and return `nil`.
4. Locate the `DefNode` at `line` using a `DefLocator` visitor (analogous to the existing `LambdaLocator` in `ConditionParser`).
5. Walk the `DefNode`'s body with the shared boolean-AST walker to produce a `ConditionTree::Node`.

> **Note:** A `DefNode` body is a `StatementsNode`; treat the last statement as the
> effective return value (same assumption `ConditionParser` makes for lambda bodies).
> Document this as a known limitation.

### 3. Recursive ref expansion (`expand_refs`)

After parsing the method body into a `ConditionTree`, walk the tree and for
each `MethodRefNode` call `resolve(node.name.to_sym, depth:, visited:)` to
obtain an expanded sub-tree, then rebuild the node with
`.with(expanded_tree: sub_tree)`.

Preserve `AndNode` / `OrNode` / `NotNode` structure by rebuilding children
with `.with` (all `ConditionTree` nodes are immutable `Data` objects).

### 4. Error handling

| Situation | Behaviour |
|---|---|
| `source_location` is `nil` | Return `nil`; no warning |
| Prism parse failure | `warn` to `$stderr`; return `nil` |
| `depth >= MAX_DEPTH` | Warn to `$stderr`; leave `MethodRefNode` with `expanded_tree: nil` |
| Cycle detected (`visited.include?`) | Return `nil`; leave `MethodRefNode` with `expanded_tree: nil` |

---

## Acceptance Criteria

- `MethodResolver.resolve(model, :some_predicate?)` returns an expanded
  `ConditionTree` for a method whose body is a boolean expression of
  predicates and method refs.
- A method that references itself (direct cycle) terminates cleanly; the
  cycle-closing `MethodRefNode` has `expanded_tree: nil`.
- An indirect cycle (A calls B calls A) terminates the same way.
- A chain exceeding `MAX_DEPTH` stops and emits a warning; the deepest
  `MethodRefNode` is left unexpanded.
- A method with no `source_location` returns `nil` without raising.
- A file that fails Prism parsing returns `nil` and emits a stderr warning.
- Extracting (if needed) the shared AST walker does not change the output of
  any existing spec.

---

## Specs (`spec/resolver/method_resolver_spec.rb`)

Cover all of:

| Scenario | Expected result |
|---|---|
| Happy path — simple predicate body | Returns `PredicateNode` |
| Nested method ref (one level deep) | Returns node with `expanded_tree` populated |
| Multi-level expansion | Each `MethodRefNode` expanded recursively |
| Direct self-cycle | Terminates; cycle node has `expanded_tree: nil` |
| Indirect cycle (A→B→A) | Terminates; cycle node has `expanded_tree: nil` |
| `MAX_DEPTH` exceeded | Stops; warns stderr; deepest node unexpanded |
| `nil` source_location | Returns `nil` |
| Prism parse failure | Returns `nil`; warns stderr |

Use RSpec doubles/fixtures or small inline Ruby classes defined via
`Class.new(ActiveRecord::Base)` (with `abstract_class = true`) so the specs
run without a real database.

---

## Risks

- **Medium:** Extracting the AST walker from `ConditionParser` without breaking
  v0.1 behaviour is the main design decision. Keep `ConditionParser`'s public
  API stable and its existing specs green.
- **Low:** `MethodRefNode#name` is a `String`; convert to `Symbol` before
  calling `instance_method`.
- **Low:** The "last statement = return value" assumption for `DefNode` bodies
  will miss methods with early returns or guard clauses — leave unexpanded
  and document the limitation.
