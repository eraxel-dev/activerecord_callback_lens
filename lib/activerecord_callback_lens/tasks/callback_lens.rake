# frozen_string_literal: true

require_relative "callback_lens_helpers"

namespace :callback_lens do
  desc "Print callback Mermaid diagram for MODEL (e.g. rake callback_lens:analyze MODEL=User)"
  task analyze: :environment do
    model_class = CallbackLensRakeHelpers.resolve_model!(ENV.fetch("MODEL", nil))
    puts CallbackLensRakeHelpers.render_mermaid(model_class)
  end

  desc "Alias for callback_lens:analyze — print Mermaid diagram for MODEL"
  task mermaid: :environment do
    model_class = CallbackLensRakeHelpers.resolve_model!(ENV.fetch("MODEL", nil))
    puts CallbackLensRakeHelpers.render_mermaid(model_class)
  end
end
