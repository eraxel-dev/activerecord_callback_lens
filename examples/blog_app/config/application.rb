# frozen_string_literal: true

require_relative "boot"

# Minimal, hand-rolled Rails boot. We deliberately avoid `require "rails/all"`
# and only pull in the frameworks this demo needs:
#   - active_record/railtie  → models, schema loading, db rake tasks
#   - rails/test_unit/railtie is intentionally omitted (no test suite here)
#
# The activerecord_callback_lens Railtie is loaded automatically by Bundler.require
# below, which is what registers the `callback_lens:*` rake tasks.
require "rails"
require "active_record/railtie"

Bundler.require(*Rails.groups)

module BlogApp
  # The demo application. Kept intentionally tiny: just enough configuration for
  # ActiveRecord models to load and boot so the gem has real callback chains to
  # analyze. This is NOT a generated `rails new` app — it is a curated minimal
  # footprint so the example reads top-to-bottom in a few files.
  class Application < Rails::Application
    config.load_defaults 8.0

    # This app is models-only; there is no `config/` autoload tree beyond what we
    # ship, no `app/controllers`, etc. Eager loading the model directory keeps the
    # boot deterministic and surfaces any model load error immediately.
    config.root = File.expand_path("..", __dir__)
    config.eager_load = true
    config.eager_load_paths << config.root.join("app", "models").to_s

    # Quieten the demo: no host authorization, no logging noise on a one-off boot.
    config.logger = Logger.new($stdout)
    config.log_level = :warn

    # The demo never serves HTTP, so disable the bits of Rails that assume a web
    # stack. Everything we need (ActiveRecord + the gem's Railtie) stays on.
    config.api_only = true
  end
end
