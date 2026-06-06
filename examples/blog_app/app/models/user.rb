# frozen_string_literal: true

# A second model so you can run the gem against `MODEL=User` and see a different,
# smaller callback graph. Demonstrates a bare create callback and a Symbol-
# conditioned update callback.
class User < ApplicationRecord
  before_create :generate_uuid
  after_update  :sync_display_name, if: :name_changed?

  # Expandable predicate: name_changed? ANDs two leaf predicates, so --expand
  # grows this into a small tree just like Article's.
  def name_changed?
    saved_change_to_first_name? || saved_change_to_last_name?
  end

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def sync_display_name
    self.display_name = [first_name, last_name].compact.join(" ")
  end
end
