# frozen_string_literal: true

require_relative "lib/activerecord_callback_lens/version"

Gem::Specification.new do |s|
  s.name        = "activerecord_callback_lens"
  s.version     = ActiverecordCallbackLens::VERSION
  s.summary     = "X-ray your ActiveRecord callbacks"
  s.description = "Inspect, parse, and visualize the callbacks registered on your " \
                  "ActiveRecord models — including their if/unless conditions — as " \
                  "graphs and diagrams."
  s.authors     = ["Eraxel.Dev"]
  s.email       = ["masacode.vancouver@gmail.com"]
  s.homepage    = "https://github.com/eraxel/activerecord_callback_lens"
  s.license     = "MIT"

  s.required_ruby_version = ">= 3.2"

  s.bindir        = "exe"
  s.executables   = ["callback_lens"]
  s.require_paths = ["lib"]
  s.files = Dir[
    "lib/**/*.rb",
    "lib/**/*.rake",
    "exe/*",
    "LICENSE",
    "README.md",
    "activerecord_callback_lens.gemspec"
  ]

  s.metadata = {
    "homepage_uri" => s.homepage,
    "source_code_uri" => s.homepage,
    "rubygems_mfa_required" => "true"
  }

  s.add_dependency "activerecord", ">= 7.0", "< 9.0"
  s.add_dependency "prism", "~> 1.0"
  s.add_dependency "thor", "~> 1.0"
end
