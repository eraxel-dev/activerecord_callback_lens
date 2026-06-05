# frozen_string_literal: true

require "activerecord_callback_lens/version"
require "activerecord_callback_lens/collector/callback_definition"
require "activerecord_callback_lens/collector/callback_collector"
require "activerecord_callback_lens/parser/condition_tree"
require "activerecord_callback_lens/railtie" if defined?(Rails::Railtie)

# Top-level namespace for the gem. Subsequent tasks append their requires above.
module ActiverecordCallbackLens
end
