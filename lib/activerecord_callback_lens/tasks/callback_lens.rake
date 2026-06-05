# frozen_string_literal: true

require_relative "callback_lens_helpers"

namespace :callback_lens do
  desc "Print callback Mermaid diagram for MODEL " \
       "(e.g. rake callback_lens:analyze MODEL=User EXPAND=true)"
  task analyze: :environment do
    model_class = CallbackLensRakeHelpers.resolve_model!(ENV.fetch("MODEL", nil))
    expand = CallbackLensRakeHelpers.expand?(ENV.fetch("EXPAND", nil))
    puts CallbackLensRakeHelpers.render_mermaid(model_class, expand: expand)
  end

  desc "Alias for callback_lens:analyze — print Mermaid diagram for MODEL"
  task mermaid: :environment do
    model_class = CallbackLensRakeHelpers.resolve_model!(ENV.fetch("MODEL", nil))
    expand = CallbackLensRakeHelpers.expand?(ENV.fetch("EXPAND", nil))
    puts CallbackLensRakeHelpers.render_mermaid(model_class, expand: expand)
  end

  desc "Write Graphviz DOT to STDOUT for MODEL " \
       "(e.g. rake callback_lens:graphviz MODEL=User EXPAND=true)"
  task graphviz: :environment do
    model_class = CallbackLensRakeHelpers.resolve_model!(ENV.fetch("MODEL", nil))
    expand = CallbackLensRakeHelpers.expand?(ENV.fetch("EXPAND", nil))
    puts CallbackLensRakeHelpers.render_graphviz(model_class, expand: expand)
  end

  desc "Write a self-contained HTML report to OUT for MODEL " \
       "(e.g. rake callback_lens:html MODEL=User OUT=report.html EXPAND=true)"
  task html: :environment do
    model_class = CallbackLensRakeHelpers.resolve_model!(ENV.fetch("MODEL", nil))
    expand = CallbackLensRakeHelpers.expand?(ENV.fetch("EXPAND", nil))
    out = ENV.fetch("OUT", "callback_lens_report.html")
    File.write(out, CallbackLensRakeHelpers.render_html(model_class, expand: expand))
    puts "Report written to #{out}"
  end
end
