# frozen_string_literal: true

require 'active_record'

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

class User < ApplicationRecord
  has_many :documents, as: :owner
  has_many :devices, as: :owner
  has_many :comments, as: :resource
end

class Document < ApplicationRecord
  belongs_to :owner, polymorphic: true
  has_many :comments, as: :resource
end

class Device < ApplicationRecord
  belongs_to :owner, polymorphic: true
  has_many :comments, as: :resource
end

class Comment < ApplicationRecord
  belongs_to :resource, polymorphic: true
end

%w[john mary paul].each do |name|
  u = User.create! name: name
  doc = Document.create! owner: u
  dev = Device.create! owner: u

  Comment.create! resource: doc
  Comment.create! resource: dev
  Comment.create! resource: u
end
