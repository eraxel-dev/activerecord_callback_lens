# frozen_string_literal: true

module ActiverecordCallbackLens
  # Rails integration hook. When the gem is loaded inside a Rails application,
  # this Railtie registers the gem's Rake tasks so that
  # +rake callback_lens:analyze MODEL=User+ works without any manual +require+.
  #
  # The file is only loaded when +Rails::Railtie+ is defined (guarded by the
  # top-level entry point), so it is a no-op outside of Rails.
  class Railtie < Rails::Railtie
    rake_tasks do
      load File.expand_path("tasks/callback_lens.rake", __dir__)
    end
  end
end
