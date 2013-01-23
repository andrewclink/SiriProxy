require 'active_record'

class Stashing < ActiveRecord::Base
  belongs_to :location
  belongs_to :thing
end