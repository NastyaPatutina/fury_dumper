require 'active_record'

class User < ActiveRecord::Base
  has_many :documents, as: :owner
  has_many :devices, as: :owner
  has_many :comments, as: :resource
end

class Document < ActiveRecord::Base
  belongs_to :owner, polymorphic: true
  has_many :comments, as: :resource
end

class Device < ActiveRecord::Base
  belongs_to :owner, polymorphic: true
  has_many :comments, as: :resource
end

class Comment < ActiveRecord::Base
  belongs_to :resource, polymorphic: true
end

['john', 'mary', 'paul'].each do |name|
  u = User.create! name: name
  doc = Document.create! owner: u
  dev = Device.create! owner: u

  Comment.create! resource: doc
  Comment.create! resource: dev
  Comment.create! resource: u
end
