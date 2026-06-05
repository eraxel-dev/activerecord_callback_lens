# Task 1: Project Scaffolding & Core Data Models

## Overview

Set up the gem skeleton and define the core data structures that all other layers depend on.

## Files to Create

```
activerecord_callback_lens.gemspec
Gemfile
lib/activerecord_callback_lens.rb
lib/activerecord_callback_lens/version.rb
lib/activerecord_callback_lens/collector/callback_definition.rb
lib/activerecord_callback_lens/parser/condition_tree.rb
```

> `exe/callback_lens` is created in Task 4, since it depends on `CLI::App` defined there. The gemspec declares the executable here so the gem structure is complete.

## Implementation Details

### gemspec

```ruby
Gem::Specification.new do |s|
  s.name          = "activerecord_callback_lens"
  s.version       = ActiverecordCallbackLens::VERSION
  s.summary       = "X-ray your ActiveRecord callbacks"
  s.executables   = ["callback_lens"]
  s.require_paths = ["lib"]

  s.add_dependency "prism"
  s.add_dependency "thor"
  s.add_dependency "activerecord", ">= 7.0"
end
```

### version.rb

```ruby
module ActiverecordCallbackLens
  VERSION = "0.1.0"
end
```

### lib/activerecord_callback_lens.rb (entry point)

Requires all submodules in dependency order. This file is created in Task 1 with the core data model requires; Tasks 2–4 add files that must be reflected here. The **final** state after all tasks is:

```ruby
require "activerecord_callback_lens/version"
require "activerecord_callback_lens/collector/callback_definition"
require "activerecord_callback_lens/parser/condition_tree"
require "activerecord_callback_lens/collector/callback_collector"
require "activerecord_callback_lens/parser/condition_parser"
require "activerecord_callback_lens/graph/nodes"
require "activerecord_callback_lens/graph/graph_builder"
require "activerecord_callback_lens/renderer/mermaid_renderer"
require "activerecord_callback_lens/cli/cli"
require "activerecord_callback_lens/railtie" if defined?(Rails::Railtie)
```

**In Task 1**, create the file with only the first three requires (version, callback_definition, condition_tree) plus the Railtie conditional. Each subsequent task appends its new file(s) to this list as part of its implementation step.

### CallbackDefinition

```ruby
CallbackDefinition = Data.define(
  :model,           # Class
  :event,           # Symbol — :save | :create | :update | :destroy | :validation
  :phase,           # Symbol — :before | :after | :around
  :filter,          # Symbol | Proc | String
  :raw_conditions,  # { if: [...], unless: [...] }
  :condition_tree,  # ConditionTree::Node | nil
  :source_location  # [String, Integer] | nil
)
```

### ConditionTree Nodes

All defined with `Data.define` under `ActiverecordCallbackLens::Parser::ConditionTree`:

| Constant | Fields | Description |
|---|---|---|
| `AndNode` | `children` | Logical AND of multiple conditions |
| `OrNode` | `children` | Logical OR of multiple conditions |
| `NotNode` | `child` | Logical negation |
| `PredicateNode` | `name` | Leaf: a single predicate method call |
| `MethodRefNode` | `name`, `expanded_tree` | Leaf: a symbol condition (`:method_name`); `expanded_tree` is `nil` in v0.1 |

## Acceptance Criteria

- [ ] `require "activerecord_callback_lens"` loads without errors
- [ ] `CallbackDefinition` and all `ConditionTree` node constants are accessible
- [ ] `gem build` succeeds with no warnings

## Spec Reference

`docs/spec.md` — Sections 1, 2, 14
