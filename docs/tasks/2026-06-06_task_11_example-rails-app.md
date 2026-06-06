# Task 11: Example Rails Application

## Overview

Add a self-contained example Rails app under `examples/blog_app/` that defines a small domain with rich ActiveRecord callbacks. The app uses SQLite and points its `Gemfile` at the parent gem via a relative path, so anyone can run every output mode (Mermaid, Graphviz, HTML, Rake tasks, programmatic API) against real models with one command.

## Goals / Success Criteria

- A working Rails app that boots and loads ActiveRecord models
- Demonstrates all gem surfaces: CLI binary, Rake tasks, programmatic API
- Demonstrates all five callback events, Proc/Symbol conditions, `if`/`unless`, and `--expand` (recursive method resolution)
- SQLite for zero external setup
- Dedicated README walking through each command with expected output
- Does NOT alter gem packaging (`examples/` is already excluded from the gemspec)

---

## Directory Structure

```
examples/blog_app/
  Gemfile                      # rails (or just activerecord+railties), sqlite3, gem via path: "../.."
  Rakefile
  config/
    application.rb
    environment.rb
    database.yml               # sqlite3 at db/blog_app.sqlite3
  app/models/
    application_record.rb
    user.rb
    article.rb
    comment.rb
  db/
    schema.rb
    seeds.rb
  bin/
    callback_lens_demo         # runs all renderers programmatically
  reports/                     # gitignored output dir
  README.md
```

---

## Models & Callbacks

### Article (showcase model — demonstrates every node type)

```ruby
before_validation :set_slug
after_validation  -> { compute_reading_time }               # Proc, no condition
before_save       :normalize_title,       if: -> { saved_change_to_title? && published? }  # Proc + AndNode
after_save        :notify_subscribers,    if: :should_notify?                              # Symbol condition (expandable)
before_create     :assign_token
after_create      :increment_author_count, unless: :draft?  # NotNode
before_update     :stamp_edited_at,        if: -> { title_changed? || body_changed? }     # OrNode
after_update      :reindex,               if: :searchable?
before_destroy    :archive,               unless: :soft_deletable?
after_destroy     :purge_cache
```

Predicate chain for `--expand` / `EXPAND=true`:

```ruby
def should_notify?
  published? && subscribers_present? && !draft?
end

def searchable?
  published? && indexable?
end
```

These give `--expand` a visibly deeper tree than the default `MethodRefNode` stub.

### User

A couple of callbacks (e.g., `before_create :generate_uuid`, `after_update :sync_display_name`) to demonstrate `MODEL=User`.

### Comment

Simple validation + `after_create :notify_article_author` to round out the demo.

---

## Implementation Phases

### Phase 1: Scaffolding & Boot

**Step 1** — `examples/blog_app/Gemfile`
- `source`, `gem "rails"` (or `activerecord` + `railties`), `gem "sqlite3"`, `gem "activerecord_callback_lens", path: "../.."`.
- Pins the example to the local in-repo gem so it always tests current code.

**Step 2** — Boot/config files: `config/application.rb`, `config/environment.rb`, `config/boot.rb`, `config/database.yml`
- Minimal `Rails::Application` subclass loading ActiveRecord + the gem's Railtie; SQLite database config.
- Railtie registration makes `callback_lens:*` Rake tasks available via the `:environment` dependency.
- **Default**: minimal hand-rolled config (smaller repo footprint). Fallback: `rails new --minimal` and trim.

**Step 3** — `Rakefile`
- `require_relative "config/application"; Rails.application.load_tasks`.
- Exposes `callback_lens:*` Rake tasks.

### Phase 2: Domain & Callbacks

**Step 4** — `app/models/application_record.rb`
- Abstract base class.

**Step 5** — `app/models/article.rb`
- Full callback set + predicate chain described above.
- The central demonstration of every node type and `--expand`.

**Step 6** — `app/models/user.rb` and `app/models/comment.rb`
- Multi-model demonstration.

**Step 7** — `db/schema.rb` (+ optional `db/seeds.rb`)
- `articles`, `users`, `comments` tables with columns that back the predicate methods.
- Note: the gem performs static analysis — it does not need a populated DB. SQLite setup is for completeness and to let the app boot as a real Rails app.

### Phase 3: Convenience Tooling

**Step 8** — `bin/callback_lens_demo`
- Load environment, run the programmatic pipeline for `Article` (and optionally all models).
- Write Mermaid / DOT / HTML to `reports/`.
- Demonstrates the programmatic API (mirrors the README's API usage section).

**Step 9** — `reports/.keep` and `.gitignore`
- Keep generated HTML/PNG/DOT out of version control.

### Phase 4: Documentation

**Step 10** — `examples/blog_app/README.md`
- Setup instructions: `bundle install`, optional `bin/rails db:prepare`.
- Command matrix covering:
  - Rake tasks: `bin/rails callback_lens:analyze MODEL=Article`, `MODEL=Article EXPAND=true`, `callback_lens:mermaid`, `callback_lens:graphviz`, `callback_lens:html OUT=reports/article.html`
  - Multi-model: `MODEL=User`, `MODEL=Comment`
  - Programmatic API via `bin/callback_lens_demo`
- Sample/expected output snippets.
- Note: Graphviz `dot` is optional; HtmlRenderer degrades gracefully without it.

**Step 11** — Top-level `README.md`
- Add a short "Example App" section with link to `examples/blog_app/` for discoverability.

---

## Verification Checklist

- [ ] `cd examples/blog_app && bundle install` succeeds
- [ ] `bin/rails runner 'p Article'` boots and prints the class
- [ ] `bin/rails callback_lens:analyze MODEL=Article` produces non-empty CLI table
- [ ] `EXPAND=true` version shows more nodes than default (predicate chain expanded)
- [ ] `bin/rails callback_lens:html MODEL=Article OUT=reports/article.html` writes a valid HTML file
- [ ] `bin/callback_lens_demo` runs without error and writes `reports/` files
- [ ] `bundle exec rspec` at the gem root still passes
- [ ] `gem build activerecord_callback_lens.gemspec` does NOT include `examples/`

---

## Open Questions / Defaults Assumed

| # | Question | Default Assumed |
|---|----------|----------------|
| 1 | Rails boot approach | Minimal hand-rolled config (smaller repo); fallback to `rails new --minimal` |
| 2 | Rails dependency scope | Full `rails` gem for simplicity; can trim to `activerecord + railties` if preferred |
| 3 | `Gemfile.lock` for example app | Gitignore it (avoids lockfile churn in the gem repo) |
| 4 | CI smoke test | Keep example purely manual/docs (no gem-suite spec for now) |
| 5 | Directory name | `examples/blog_app/` |

---

## Risks & Mitigations

- **Medium** — Minimal Rails boot config is fiddly across Rails versions. Mitigation: fall back to `rails new --minimal` if hand-rolled config fails.
- **Low** — `path: "../.."` Gemfile reference + separate `Gemfile.lock` could drift. Mitigation: gitignore example's lockfile.
- **Low** — Graphviz `dot` not installed on a user's machine breaks HTML SVG section. Mitigation: HtmlRenderer already degrades gracefully; README documents `dot` as optional.
- **Low** — Adding `rails` in `examples/` could confuse contributors. Mitigation: example has its own isolated `Gemfile`; gem root `Gemfile` is untouched.

## Complexity Estimate

**Low-to-Medium.** The gem code is entirely untouched — this is additive scaffolding + docs only. Phase 1 (Rails boot config) is ~40% of the effort; all other phases are straightforward.
