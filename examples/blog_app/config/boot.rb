# frozen_string_literal: true

# Standard Rails boot shim: point Bundler at this app's own Gemfile and load the
# gems in the default + current-environment groups. Setting BUNDLE_GEMFILE
# explicitly means the app boots correctly no matter which directory you invoke
# `bin/rails` from.
ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup"
