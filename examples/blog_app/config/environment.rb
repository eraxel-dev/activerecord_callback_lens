# frozen_string_literal: true

# Load the application definition, then finish booting it. `bin/rails` and the
# rake tasks' `:environment` prerequisite both require this file, which is what
# makes the models available to `callback_lens:*` tasks and `rails runner`.
require_relative "application"

Rails.application.initialize!
