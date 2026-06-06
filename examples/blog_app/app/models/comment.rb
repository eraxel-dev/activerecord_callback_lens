# frozen_string_literal: true

# The smallest model in the demo: a validation plus a single after_create
# callback. Rounds out the multi-model story (`MODEL=Comment`).
class Comment < ApplicationRecord
  validates :body, presence: true

  after_create :notify_article_author, unless: :author_is_commenter?

  def author_is_commenter?
    article_author_id == commenter_id
  end

  def notify_article_author; end
end
