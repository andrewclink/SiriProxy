require 'active_record'

class Owner < ActiveRecord::Base
  has_many :things
  has_many :locations
  
  before_save do
    self.first_name.strip!
    self.last_name.strip!
  end
end