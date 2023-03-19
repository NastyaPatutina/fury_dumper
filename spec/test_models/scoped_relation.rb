# frozen_string_literal: true

require 'active_record'

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

class Document < ApplicationRecord
  belongs_to :user
end

class User < ApplicationRecord
  has_many :documents, -> { where.not(status: 'actual') }, class_name: 'Document'
  has_many :actual_documents, -> { where(status: 'actual') }, class_name: 'Document'
end

%w[john mary paul].each do |name|
  u = User.create! name: name
  Document.create! user: u, status: 'actual'
  Document.create! user: u, status: 'old'
end
