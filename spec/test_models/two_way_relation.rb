require 'active_record'

class Document < ActiveRecord::Base
  belongs_to :user
end

class User < ActiveRecord::Base
  has_many :documents, dependent: :destroy
end

['john', 'mary', 'paul'].each do |name|
  u = User.create! name: name
  Document.create! user: u
end
