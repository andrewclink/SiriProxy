require 'cora'
require 'siri_objects'
require 'pp'

require 'active_record'
require 'sqlite3'
require 'logger'
 
class SiriProxy::Plugin::LostFound < SiriProxy::Plugin
  
  attr_accessor :wants_person, :current_fiber, :firstName, :lastName
  
  def initialize(config)
    puts "Initializing Lost & Found"

    database_config = YAML::load(File.open(File.join(config['path'], "database.yml")))
    
    database_config.each do |key, value|
      puts "Checking #{key}"
      if value["database"]
        
        value["database"] = File.join(config['path'], value["database"])

        puts "-> Found Database #{File.join(Dir.pwd, value["database"])}"

      end
    end
    
    ActiveRecord::Base.logger = Logger.new(File.join(config['path'], 'debug.log'))
    ActiveRecord::Base.configurations = database_config
    ActiveRecord::Base.establish_connection('development')
    
    load_dependencies
  end
  
  def load_dependencies
    puts "-> Loading Models..."

    Dir["#{File.dirname(__FILE__)}/models/*.rb"].each do |f| 
      puts "-> Loading #{f}"
      load(f)
    end
  end

  # Notice who we're talking to...
  #
  filter "PersonSearchCompleted" do |object|
    puts "[Info - PersonSearchCompleted] Object:"
    results = object["properties"]["results"]
    contact = nil
    
    if results.length < 1
      puts " -> No Results"
    else
      contact = results[0]["properties"]
    end
    
    ## Log
    fname = contact['firstName']
    lname = contact['lastName']
    puts "Filter-> Name: #{fname} #{lname} (wants_person = #{@wants_person})"
    
    if @wants_person
      @callback.call(contact) rescue nil
      false
    else
      nil
    end
  end
  
  def fetch_current_person
    fetch_person(:me)
  end
  
  def fetch_person(query = :me)
    f = Fiber.current
    @current_fiber = f
    @wants_person = true
    
    s = SiriPersonSearch.new("PersonSearch", "com.apple.ace.contact")
    
    if :me == query
      s.properties["me"] = "true"
    else
      s.properties["name"] = query.to_s
    end
    s.properties["scope"] = "Local"
    s.make_root(last_ref_id)
    

    ## Start PersonSearch
    puts "-> Sending PersonSearch Request"
    send_object s, target: :iphone

    ## Set Callback
    fname = nil
    lname = nil

    # manager.set_callback do |person|
    @callback = Proc.new do |person|
      fname = person['firstName']
      lname = person['lastName']
      puts "-> Callback: Name: #{fname} #{lname}"
       @wants_person = false
      f.resume() if f.alive?
    end

    # Thread.new do 
    #   sleep 5
    #   if f_yielding
    #     puts "-> Timed out"
    #     manager.set_callback {}
    #     f.resume
    #     f_yielding = false
    #   end
    # end

    puts "-> Waiting"
    Fiber.yield
    
    return fname, lname
  end

#pragma mark - Testing
    
  listen_for /test lost and found/i do
    say "Lost and found is available"
    request_completed
  end
  
  listen_for /What(:?\'?s)? my name/i do |test|

    first_name, last_name = fetch_current_person
    say "Looks like you're #{first_name} #{last_name}"

    request_completed
  end
  
#pragma mark - Development

  listen_for /reload (?:the )?lost and found schema/i do
  say "Reloading schema..."
  schema = Schema.new
  schema.down
  schema.up
  say "Ok, all set."
  request_completed
  end

  listen_for /reload/i do
   load_dependencies
   load __FILE__
 
   say "@{tts#\e\\rate=40\\}Whoa, @{tts#\e\\rate=100\\}what just happened there?"
   request_completed
  end

#pragma mark - Accessors

  def fetch_owner(query=:me)
    # Fetch owner from database
    first_name, last_name = fetch_person(query)
    owner_params = {:first_name => first_name, :last_name => last_name}
    owner = Owner.where(owner_params).first
    owner = Owner.new(owner_params) if owner.nil?

    return owner
  end

#pragma mark - Stashing Things in Locations

  def siri_understood_possesive(posessive)
    return "your" if posessive =~ /my/i
    return posessive
  end
  
  def owner_for_possesive(possesive)
    owner = nil

    return owner if possesive =~ /the|our/i
    return fetch_owner(:me) if possesive =~ /my/i
    
    if posessive.match(/([\w\s])+\'s/i)
      owner = fetch_owner(match.captures[1])
    end
  end
  
  
  def put_thing_in_location(object_possesive, object, vicinity, location_possive, location)
    owner = fetch_owner

    # Find that person's thing.
    thing_params = {:name => object}
    thing = owner.things.where(thing_params).first

    if thing.nil?
      # Check if there's an unowned thing
      thing = Thing.where(thing_params.merge(:owner_id => nil)).first
    end

    if thing.nil?
      # Check if they're fuzzy on ownership
      thing = Thing.where(thing_params).first
      if (thing && thing.owner)
        response = ask("Is this the same as #{thing.owner.firstname}'s #{thing.name}?")
        thing = nil if response =~ DENY_REGEX
      end
    end
      
    if thing.nil?
      thing = Thing.new(thing_params)
      thing.owner = owner_for_possesive(object_possesive)
      thing.save
    end
      
    loc = nil
    loc_owner = owner_for_possesive(location_possive)
    loc = loc_owner.locations.where(:name => location.strip).first unless loc_owner.nil?
    loc = Location.where(:name => location.strip).first if location.nil?
    if loc.nil?
      loc = Location.new(:name => location.strip, :owner => loc_owner)
      puts "-> Creating location #{loc.inspect}"
      loc.save
    end
    

    if (thing.stash_at(loc, vicinity))
      puts "Stashed at: #{thing.most_recent_stashing}"
      say "Ok, #{siri_understood_possesive(object_possesive)} #{object} is #{vicinity} the #{location}"
    else
      say "Couldn't stash #{object} #{vicinity} #{location}"
    end

  end
  
  listen_for /(?:Siri )?(?:I left|I'm leaving) (my|the|our) ([\w\s]+?) (on|at|near|by|on top of|in(?:side)?) (my|the|our) ([\w\s]+)\s*/i do |object_possesive, object, vicinity, location_possive, location| #'
    put_thing_in_location(object_possesive, object, vicinity, location_possive, location)
    request_completed
  end

  listen_for /(?:Siri )?(my|the|our) ([\w\s]+?) (?:is|are) (on|at|near|by|on top of|in(?:side)?) (my|the|our) ([\w\s]+)\s*/i do |object_possesive, object, vicinity, location_possive, location| #'
    put_thing_in_location(object_possesive, object, vicinity, location_possive, location)
    request_completed
  end
  
  
  #pragma mark - Locating Things
  
  listen_for /tell me about the ([\w\s]+)/i do |object|
    object.strip!
    
    thing = Thing.find_by_name(object)
    if thing.nil? 
      puts "Thing   : #{thing.inspect} (Searched for name=> #{object})"
      say "I don't know about the #{object}"
    else
      
      owner = fetch_owner
      
      stashing = thing.most_recent_stashing
      
      puts "Thing   : #{thing.inspect}"
      puts "Stashing: #{stashing.inspect}"
      puts "Loc Arcl: #{location_article(stashing, owner) rescue "Exception"}"
      puts "Location: #{stashing.location.inspect rescue nil}"
      say "The #{thing.name} is stashed #{stashing.vicinity} #{location_article(stashing, owner)} #{stashing.location.name}"
      
    end
    
    request_completed
  end

  listen_for /where(?:''?|\si)s my stuff/i do
    stashings = Stashing.find(:all, :limit => 3)
    
    say "I know about these:"
    stashings.each do |s|
      say "#{s.thing.name} in #{s.location.name}"
    end
    
    request_completed
  end
  
  def location_article(stashing, owner)
    return "the" if nil == owner 
    
    # Figure out the stashing's location's owner
    loc_owner = stashing.location.owner rescue nil
    return "the" if loc_owner.nil?
    
    # If this is mine, say "your place"
    return "your" if loc_owner == owner
    
    #loc_owner isn't nil, so say "their place"
    return loc_owner.first_name + "'s"
  end
  
  def locate_thing(posessive, thing_name)
    puts "-> Searching for '#{thing_name}'"
    
    thing = Thing.find_by_name(thing_name.strip)

    if thing.nil?
      say "Sorry, but I don't know where #{siri_understood_possesive(posessive)} #{thing_name} is."
      return
    end


    s = thing.most_recent_stashing
    delta = Time.now - s.created_at

    puts "-> Found #{s.inspect}"

    owner = fetch_owner
    the = location_article(s, owner)

    if delta < (60 * 5)
      # less than 5 minutes
      say "You just told me it was #{s.vicinity || "near"} #{the} #{s.location.name}"
    elsif delta > 86400
      say "It was #{s.vicinity || "near"} #{the} #{s.location.name} yesterday"
    else
      say "Last I knew, it was #{s.vicinity || "near"} #{the} #{s.location.name}"
    end
  end
  
  listen_for /where(?:''?|\si)s (my|the|our) ([\w\s]+)/i do |posessive, thing_name|
    locate_thing(posessive, thing_name)
    request_completed
  end

  listen_for /where(?:''?|\sdi)d I leave (my|the|our) ([\w\s]+)/i do |posessive, thing_name|
    locate_thing(posessive, thing_name)
    request_completed
  end

  
  listen_for /test Stashing/i do 
    puts Stashing.inspect
    say "Ok."
    request_completed
  end

end
