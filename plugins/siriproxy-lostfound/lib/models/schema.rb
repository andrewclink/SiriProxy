class Schema < ActiveRecord::Migration
  def up
   create_table :locations, :force => true do |t|
     t.integer :owner_id # nil=> "the place", andrew=> "your place", monica => "Monica's place"
     t.string :name
     t.timestamps
   end 
   add_index :locations, :name


   
   create_table :owners, :force => true do |t|
     t.string :first_name
     t.string :last_name
     t.timestamps
   end



   create_table :things, :force => true do |t|
     t.integer :owner_id
     t.string :name
     t.timestamps
   end
   add_index :things, :name



   create_table :stashings, :force => true do |t|
     t.integer :location_id
     t.integer :thing_id
     t.string :vicinity
     t.timestamps
   end
   add_index :stashings, :location_id
   add_index :stashings, :thing_id
  end
  
  def down
    drop_table :locations rescue nil
    drop_table :owners    rescue nil
    drop_table :things    rescue nil
    drop_table :stashings rescue nil
  end
    
end
