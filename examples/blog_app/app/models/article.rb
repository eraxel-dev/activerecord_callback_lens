# frozen_string_literal: true

# The showcase model. Article registers a callback for every one of the five
# ActiveRecord lifecycle events (validation, save, create, update, destroy) and
# every condition style the gem understands:
#
#   - bare Symbol callbacks (no condition)        → set_slug, assign_token, ...
#   - Proc/lambda callbacks                       → after_validation lambda
#   - `if:` with a Proc that ANDs predicates      → before_save  (AndNode)
#   - `if:` with a Proc that ORs predicates       → before_update (OrNode)
#   - `if:` with a Symbol condition               → after_save, after_update
#   - `unless:` (negation)                        → after_create, before_destroy (NotNode)
#
# The Symbol conditions `should_notify?` and `searchable?` delegate to *other*
# predicates. That is what makes `--expand` / `EXPAND=true` worthwhile: the
# resolver reads each method's source, parses the boolean expression, and grows
# the dependency tree several levels deeper than the default `MethodRefNode` stub.
class Article < ApplicationRecord
  # ---- Validation ---------------------------------------------------------
  before_validation :set_slug
  after_validation  -> { compute_reading_time } # Proc, no condition

  # ---- Save ---------------------------------------------------------------
  # Proc condition combining two predicates with && → AndNode
  before_save :normalize_title, if: -> { saved_change_to_title? && published? }
  # Symbol condition → MethodRefNode, expandable via --expand
  after_save  :notify_subscribers, if: :should_notify?

  # ---- Create -------------------------------------------------------------
  before_create :assign_token
  # `unless:` → NotNode wrapping a MethodRefNode
  after_create  :increment_author_count, unless: :draft?

  # ---- Update -------------------------------------------------------------
  # Proc condition combining two predicates with || → OrNode
  before_update :stamp_edited_at, if: -> { title_changed? || body_changed? }
  # Symbol condition → MethodRefNode, expandable via --expand
  after_update  :reindex, if: :searchable?

  # ---- Destroy ------------------------------------------------------------
  before_destroy :archive, unless: :soft_deletable?
  after_destroy  :purge_cache

  # === Predicate chain (the meat for --expand) =============================
  # The resolver treats the LAST statement of a method body as its return value,
  # so each of these is a single boolean expression of further predicates.

  # Expands to: published? && subscribers_present? && !draft?
  def should_notify?
    published? && subscribers_present? && !draft?
  end

  # Expands to: published? && indexable?
  def searchable?
    published? && indexable?
  end

  # === Leaf predicates =====================================================
  # Some are backed by real columns (via the schema); the rest are plain Ruby so
  # the model loads cleanly. None of these need to be *correct* domain logic —
  # they exist to give the analyzer real predicate names to graph.

  def published?
    status == "published"
  end

  def draft?
    status == "draft"
  end

  def subscribers_present?
    subscriber_count.to_i.positive?
  end

  def indexable?
    !draft? && body.present?
  end

  def soft_deletable?
    respond_to?(:archived_at) && archived_at.present?
  end

  # === Callback bodies =====================================================
  # No-op implementations: the gem analyzes statically and never runs these, but
  # defining them keeps Article a believable, fully-formed model.

  def set_slug
    self.slug = title.to_s.parameterize if title.present?
  end

  def compute_reading_time
    self.reading_time_minutes = (body.to_s.split.size / 200.0).ceil
  end

  def normalize_title
    self.title = title.to_s.strip.squeeze(" ")
  end

  def notify_subscribers; end
  def assign_token = self.token ||= SecureRandom.hex(8)
  def increment_author_count; end
  def stamp_edited_at = self.edited_at = Time.current
  def reindex; end
  def archive = self.archived_at = Time.current
  def purge_cache; end
end
