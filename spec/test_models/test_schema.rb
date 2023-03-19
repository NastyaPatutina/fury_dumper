# frozen_string_literal: true

require 'active_record'

ActiveRecord::Schema.define do
  self.verbose = false

  create_table 'users', force: :cascade do |t|
    t.string 'name'
  end

  create_table 'documents', force: :cascade do |t|
    t.integer 'user_id'
    t.integer 'owner_id'
    t.string 'owner_type'
    t.string 'status'
  end

  create_table 'devices', force: :cascade do |t|
    t.integer 'owner_id'
    t.string 'owner_type'
    t.string 'status'
  end

  create_table 'comments', force: :cascade do |t|
    t.integer 'resource_id'
    t.string 'resource_type'
  end
end
