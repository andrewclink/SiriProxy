require 'active_record'

class Thing < ActiveRecord::Base
  has_many :stashings, :order => "created_at DESC"
  belongs_to :owner

  before_save do
    self.name.strip!
  end
  
  def most_recent_stashing
    self.stashings.first
  end
  
  def stash_at(location, vicinity=nil)
    self.save if self.new_record?
    location.save if location.new_record?
    
    stashing = Stashing.new
    stashing.thing = self
    stashing.location = location
    stashing.vicinity = vicinity
    stashing.save
  end
end