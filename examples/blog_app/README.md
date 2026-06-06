# blog_app — activerecord_callback_lens example

A tiny, self-contained Rails app that exists for one reason: to give
[`activerecord_callback_lens`](../../README.md) real ActiveRecord models with
rich callbacks to analyze. It boots on SQLite (zero setup) and points its
`Gemfile` at the gem in this repo (`path: "../.."`), so every command below runs
against the **current in-repo gem code**.

The domain is a minimal blog:

| Model | Why it's here |
|---|---|
| **Article** | The showcase. One callback for every lifecycle event, every condition style (Proc `&&`/`\|\|`, Symbol, `if:`/`unless:`), plus a predicate chain that makes `--expand` worthwhile. |
| **User** | A smaller graph for `MODEL=User`. |
| **Comment** | The smallest model, to round out the multi-model demo. |

---

## Setup

```bash
cd examples/blog_app
bundle install
```

> The example keeps its own `Gemfile.lock` (gitignored). It does **not** share a
> bundle with the gem.

Populating the database is **optional** — the gem analyzes callbacks statically
and never queries your tables. If you want real rows for poking around in a
console:

```bash
bin/rails db:prepare   # create the SQLite DB and load db/schema.rb
bin/rails db:seed      # optional sample data
```

Sanity-check that the app boots and loads models:

```bash
bin/rails runner 'p Article'
# => Article(...)   # prints the class with its columns
```

---

## Command matrix

All rake tasks are registered automatically by the gem's Railtie — no `require`
needed. `MODEL` is required; `EXPAND` and `OUT` are optional.

### Rake tasks

```bash
# Mermaid diagram to stdout (analyze and mermaid are aliases)
bin/rails callback_lens:analyze MODEL=Article
bin/rails callback_lens:mermaid MODEL=Article

# Recursively expand Symbol conditions (should_notify?, searchable?) into their
# underlying predicate trees — visibly more nodes than the default.
bin/rails callback_lens:analyze MODEL=Article EXPAND=true

# Graphviz DOT to stdout (pipe to `dot` if installed)
bin/rails callback_lens:graphviz MODEL=Article
bin/rails callback_lens:graphviz MODEL=Article | dot -Tpng -o reports/article.png

# Self-contained HTML report
bin/rails callback_lens:html MODEL=Article OUT=reports/article.html
bin/rails callback_lens:html MODEL=Article OUT=reports/article_expanded.html EXPAND=true
```

### Other models

```bash
bin/rails callback_lens:analyze MODEL=User
bin/rails callback_lens:analyze MODEL=Comment
```

### Programmatic API

`bin/callback_lens_demo` boots the environment and drives the gem via plain Ruby
(collect → parse → expand → build → render), writing Mermaid `.mmd`, Graphviz
`.dot`, and `.html` for each model into `reports/`:

```bash
bin/callback_lens_demo                # all models, no expansion
bin/callback_lens_demo Article        # a single model
EXPAND=true bin/callback_lens_demo    # recursively expand Symbol conditions
```

### CLI binary (bonus)

The `callback_lens` binary works too, as long as the model is loaded. Wrap it in
`rails runner` so the environment is available:

```bash
bin/rails runner 'require "activerecord_callback_lens"; ActiverecordCallbackLens::CLI::App.start(["analyze", "Article", "--expand"])'
```

---

## What the output looks like

`bin/rails callback_lens:analyze MODEL=Article` prints a Mermaid `graph TD`. The
default run leaves Symbol conditions as single `MethodRefNode` leaves:

```text
graph TD
  ...
  nX["after_save"]
  nY["should_notify?"]
  nY --> nX
  ...
```

With `EXPAND=true`, `should_notify?` is resolved into
`published? && subscribers_present? && !draft?`, so the same callback grows a
deeper subtree:

```text
graph TD
  ...
  nX["after_save"]
  nA["AndNode"]
  nB["published?"]
  nC["subscribers_present?"]
  nD["NotNode"]
  nE["draft?"]
  ...
```

(The exact node ids vary; the point is that `EXPAND=true` produces strictly more
nodes than the default for `Article`.)

---

## Notes

- **Graphviz `dot` is optional.** The HTML report embeds an inline SVG only when
  `dot` is installed; without it the report still renders (the SVG section
  degrades gracefully). Install Graphviz from <https://graphviz.org/download/> if
  you want the SVG and `.png` output.
- **No database required.** The gem reads callback chains statically from the
  loaded model classes. `db:prepare`/`db:seed` are conveniences, not
  prerequisites for any `callback_lens:*` command.
- **This app is intentionally hand-rolled** (not `rails new`) to keep the
  footprint small and readable — a handful of files under `config/`, `app/`, and
  `db/`.
