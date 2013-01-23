require 'active_record'

class Location < ActiveRecord::Base
  belongs_to :owner
  has_many :stashings, :order => "created_at DESC"
  
  before_save do
    self.name.strip!
  end
end