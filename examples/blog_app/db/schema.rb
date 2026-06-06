# frozen_string_literal: true

# Hand-written schema (no migrations dir for this tiny demo). Load it with:
#
#   bin/rails db:prepare        # creates the DB and loads this schema
#   # or:
#   bin/rails runner 'load Rails.root.join("db/schema.rb").to_s'
#
# The columns exist to back the predicate/callback methods on the models so the
# app boots as a real Rails app. The gem itself reads callbacks statically and
# never touches these tables, so a populated database is entirely optional.
#
# A schema DSL block is one long table-definition block by design (the same
# rationale RuboCop's default config applies to migrations), so BlockLength is
# disabled for it.
# rubocop:disable Metrics/BlockLength
ActiveRecord::Schema[8.0].define(version: 0) do
  create_table :articles, force: true do |t|
    t.string  :title
    t.string  :slug
    t.text    :body
    t.string  :status, default: "draft", null: false
    t.integer :reading_time_minutes
    t.integer :subscriber_count, default: 0, null: false
    t.string  :token
    t.bigint  :author_id
    t.datetime :edited_at
    t.datetime :archived_at
    t.timestamps
  end

  create_table :users, force: true do |t|
    t.string :uuid
    t.string :first_name
    t.string :last_name
    t.string :display_name
    t.timestamps
  end

  create_table :comments, force: true do |t|
    t.text    :body
    t.bigint  :article_id
    t.bigint  :article_author_id
    t.bigint  :commenter_id
    t.timestamps
  end
end
# rubocop:enable Metrics/BlockLength
