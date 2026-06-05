# Task 2: Collector Layer

## Overview

Implement `CallbackCollector`, which reads ActiveRecord's internal callback chains and returns an array of `CallbackDefinition` structs with raw condition data ready for the parser.

## Dependency

Requires Task 1 (`CallbackDefinition` data model).

## Files to Create

```
lib/activerecord_callback_lens/collector/callback_collector.rb
```

## Implementation Details

### Public API

```ruby
# Collect all callbacks registered on a model class.
# @param model_class [Class] an ActiveRecord::Base subclass
# @return [Array<Collector::CallbackDefinition>]
CallbackCollector.collect(model_class)
```

### ActiveRecord Chain Accessors

| Event | Accessor |
|---|---|
| `:save` | `_save_callbacks` |
| `:create` | `_create_callbacks` |
| `:update` | `_update_callbacks` |
| `:destroy` | `_destroy_callbacks` |
| `:validation` | `_validation_callbacks` |

Each chain is accessed via `model_class.send(accessor)`.

### Per-callback Extraction

From each `ActiveSupport::Callbacks::Callback` object:

- `cb.kind` → `:before | :after | :around` (stored as `phase`)
- `cb.filter` → `Symbol | Proc | String` (stored as `filter`)
- `cb.instance_variable_get(:@if)` → Array (stored in `raw_conditions[:if]`)
- `cb.instance_variable_get(:@unless)` → Array (stored in `raw_conditions[:unless]`)

### source_location Resolution

```ruby
def resolve_location(filter)
  case filter
  when Proc   then filter.source_location  # [file, line]
  when Symbol then nil                     # resolved later by MethodResolver (v0.2)
  end
end
```

### Returned Definition State

All returned `CallbackDefinition` structs have `condition_tree: nil`. The Parser layer (Task 3) populates this field.

## Update Entry Point

After creating `callback_collector.rb`, add the following line to `lib/activerecord_callback_lens.rb` (after the `callback_definition` require):

```ruby
require "activerecord_callback_lens/collector/callback_collector"
```

## Acceptance Criteria

- [ ] `CallbackCollector.collect(User)` returns an array of `CallbackDefinition` objects
- [ ] Each definition has correct `event`, `phase`, `filter`, and `raw_conditions`
- [ ] Proc filters have `source_location` populated; Symbol filters have `nil`
- [ ] All 5 event types are enumerated

## Spec Reference

`docs/spec.md` — Section 3
