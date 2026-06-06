# frozen_string_literal: true

# Abstract base class for every model in the demo, mirroring the convention a
# real Rails app uses. Nothing special here — it exists so the concrete models
# read like production code.
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
