# frozen_string_literal: true

# Optional sample data. The gem analyzes callbacks statically and does not need
# any rows, so seeding is purely for folks who want to poke at the models in a
# console (`bin/rails runner` or a REPL). Run with `bin/rails db:seed` after
# `bin/rails db:prepare`.
author = User.create!(first_name: "Ada", last_name: "Lovelace", uuid: SecureRandom.uuid)

article = Article.create!(
  title: "Hello, Callbacks",
  body: "A short post about ActiveRecord callbacks." * 10,
  status: "published",
  subscriber_count: 3,
  author_id: author.id
)

Comment.create!(
  body: "Great write-up!",
  article_id: article.id,
  article_author_id: author.id,
  commenter_id: author.id + 1
)

puts "Seeded #{User.count} user(s), #{Article.count} article(s), #{Comment.count} comment(s)."
