# Rails Callback Dependency Analyzer Design Document

## Overview

A gem that statically analyzes ActiveRecord callbacks to visualize conditions, dependencies, and execution order.

### Key Technologies

-   ActiveRecord callback introspection
-   Prism (Ruby AST)
-   RBS (optional)
-   Graphviz
-   Mermaid

## Architecture

``` text
callback_analyzer

 ├─ collector/
 ├─ parser/
 ├─ resolver/
 ├─ graph/
 ├─ renderer/
 ├─ cli/
 └─ runtime/
```

## Core Models

### CallbackDefinition

-   model
-   event
-   phase
-   filter
-   condition_tree
-   source_location

### ConditionTree

-   ConditionNode
-   AndNode
-   OrNode
-   NotNode
-   PredicateNode
-   MethodRefNode

## Collector Layer

APIs used:

-   `_save_callbacks`
-   `_create_callbacks`
-   `_update_callbacks`
-   `_destroy_callbacks`
-   `_validation_callbacks`

Information retrieved:

-   kind
-   filter
-   if
-   unless

## Prism Analysis

### Proc/Lambda

After retrieving source_location, parse into AST with Prism.

Example:

``` ruby
if: -> {
  saved_change_to_title? &&
  status_completed?
}
```

Converted to:

``` text
AND
├─ saved_change_to_title?
└─ status_completed?
```

### Supported Nodes

-   AndNode
-   OrNode
-   NotNode
-   CallNode

## Method Resolver

``` ruby
if: :sync_required?
```

Analyzes the definition source and recursively expands it.

Example:

``` ruby
def sync_required?
  publishable? &&
  changed?
end

def publishable?
  approved? &&
  visible?
end
```

Result:

``` text
AND
├─ changed?
└─ publishable?
    ├─ approved?
    └─ visible?
```

### Controls

-   max_depth = 5
-   Cycle detection via visited Set

## Graph Builder

Builds a DAG.

Node types:

-   CallbackNode
-   ConditionNode
-   MethodNode
-   PredicateNode

## ExecutionOrder Analyzer

Reproduces the order of operations during a save.

Example:

1.  before_validation
2.  before_save
3.  before_create
4.  after_create
5.  after_save
6.  after_commit

## Mermaid Renderer

``` mermaid
graph TD

A[saved_change_to_title?]
B[status_completed?]

A --> AND1
B --> AND1

AND1 --> sync_required
sync_required --> sync_to_crm
```

## Graphviz Renderer

Outputs DOT format.

``` dot
digraph {
  A -> AND1
  B -> AND1
}
```

## HTML Renderer

Output includes:

-   Callback list
-   Execution Flow
-   Dependency Tree
-   Mermaid
-   Graphviz SVG

## Runtime Tracer

Uses ActiveSupport::Notifications.

Collects:

-   Callback name
-   Duration
-   Result

## CLI

``` bash
callback_analyzer User
callback_analyzer User --expand
callback_analyzer User --mermaid
callback_analyzer User --graphviz
callback_analyzer User --html
callback_analyzer User --trace
```

## Roadmap

### v0.1

-   CallbackCollector
-   Prism Parser
-   Mermaid

### v0.2

-   Method Resolver
-   Recursive expansion

### v0.3

-   Graphviz

### v0.4

-   HTML

### v1.0

-   Runtime Tracer

### v2.0

-   RBS analysis
-   Cross-model dependency graph
