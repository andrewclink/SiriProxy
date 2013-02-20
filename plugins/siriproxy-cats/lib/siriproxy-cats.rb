require 'cora'
require 'siri_objects'
require 'pp'
require 'socket'

require 'fileutils'
require 'date_helper_bastardized'

#######
# This is a "hello world" style plugin. It simply intercepts the phrase "test siri proxy" and responds
# with a message about the proxy being up and running (along with a couple other core features). This
# is good base code for other plugins.
#
# Remember to add other plugins to the "config.yml" file if you create them!
######

class SiriProxy::Plugin::Cats < SiriProxy::Plugin
  
  attr_accessor :current_fiber
  
  def initialize(config)
    #if you have custom configuration options, process them here!
  end

  LAST_FED_LOCK = "/tmp/food-lastfed"
  HEARTBEAT_FILE = "/tmp/food-heartbeat"

  FOOD_ADDR = "172.16.1.3"
  FOOD_PORT = 2020
  
  def send_food(speed)
    # Speed is 8-bit
    if (speed > 255) 
      speed = 255
    end

    cmd = ['o'.ord, speed].pack("c*")

    s = UDPSocket.new
    s.send(cmd, 0, FOOD_ADDR, FOOD_PORT)
    
    # Update last fed lockfile
    FileUtils.touch(LAST_FED_LOCK)
    
  end


  listen_for /feed (?:my|the|our) cat(:?s?)(:?\,? please)?/i do
    say "Ok, I'll feed the cats for you."
    send_food(1)
    request_completed
  end
  
  listen_for /give (?:my|the|our) cat(?:[\''s]+?) a?\s*(little bit|lot|ton) of food(?:\,? please)?/i do |amount|
    speed = case amount
    when /little/   then 1
    when /lot/      then 2
    when /ton/      then 3
    else 1
    end
    
    say "Ok, I'll give them a #{amount} bit of food."
    send_food(speed)

    request_completed
  end
  
  listen_for /When wh?ere (?:my|the|our) cat(?:s?) (?:last ?|[bf]ed ?){2,}/i do
    respond_to_last_fed_query
  end
  
  listen_for /When(?:\'s|was|') the last time you fed (?:my|the|our) cat(?:s?)/ do
    respond_to_last_fed_query
  end
  
  listen_for /When wh?ere (?:my|the|our) cat(?:s?) fed/ do
    respond_to_last_fed_query
  end
  
  
  def respond_to_last_fed_query
    mod_time = nil

    begin
      mod_time = File.mtime(LAST_FED_LOCK) rescue nil
      time_ago = Time.now - mod_time
    rescue 
      mod_time = nil
    end
    
    ask_to_feed = false
    
    last_fed_verbal = case time_ago
    when (0..10) then "just a moment ago"
    when (10..21600) then "#{time_ago_in_words(mod_time)} ago"  #10 seconds - 6 hours
    when (21600..86400) then 
      ask_to_feed = true
      "earlier today, at #{mod_time.strftime("%I:%H")}"
    else nil
    end
    
    
    ##
    ## Tell When fed
    if last_fed_verbal.nil?
      ask_to_feed = true
      say "I'm really sorry, but I actually don't know."
    else
      say "Looks like they were fed #{last_fed_verbal}"
    end
    
    
    ##
    ## Ask to feed again if appropriate
    if ask_to_feed && ask_to_feed_now
      send_food(2)
    end
  end


  listen_for /how are the cats/i do
    
    ask_to_feed = false

    ##
    ## Heartbeat
    last_heartbeat = File.mtime(HEARTBEAT_FILE)
    heartbeat_phrase = if (Time.now - last_heartbeat < 10)
      "Doing Well!"
    else
      ask_to_feed = true
      "Bad news..."
    end
    
    ##
    ## Last Feed Time
    mod_time = nil
    begin
      mod_time = File.mtime(LAST_FED_LOCK) rescue nil
      time_ago = Time.now - mod_time
    rescue 
      mod_time = nil
    end

    last_fed_verbal = case time_ago
    when (0..10) then "and I just fed them a moment ago"
    when (10..21600) then "and they were fed #{time_ago_in_words(mod_time)} ago"  #10 seconds - 6 hours
    when (21600..86400) then 
      ask_to_feed = true
      "and they were fed earlier today, at #{mod_time.strftime("%I:%H")}"
    else 
      ask_to_feed = true
      "but I don't know when they were last fed."
    end
    

    # This crashes siri:
    # say heartbeat_phrase
    # say "Received a heartbeat #{time_ago_in_words(last_heartbeat)} ago, " +
    #     "#{last_fed_verbal} ago."
    
    # say heartbeat_phrase
    say "Received a heartbeat #{time_ago_in_words(last_heartbeat)} ago, " +
        "#{last_fed_verbal}."

    ask_to_feed_now if ask_to_feed
    
    request_completed
  end
  

  def ask_to_feed_now(ask_phrase="Would you like me to feed them now?")
    @ask_to_feed_attempt = 0 if @ask_to_feed_attempt.nil?
    puts "Ask attempt #{@ask_to_feed_attempt}"
    
    @ask_to_feed_attempt += 1

    response = ask ask_phrase
    
    if response =~ DENY_REGEX
      say "Ok, I don't eat either."
      @ask_to_feed_attempt = 0
      return false
    elsif response =~ CONFIRM_REGEX
      say "Ok, I'll feed them now."
      @ask_to_feed_attempt = 0
      return true
    else
      case @ask_to_feed_attempt
      when 1 then
        say "Sorry, I didn't get that."
        ask_phrase = "Should I feed the cats?"
      when 2 then 
        say "Uh, sorry..."
        ask_phrase = "Feed the cats or no?"
      when 3 then 
        say "And some gibberish to you, too."
        ask_phrase = "Should I feed the cats, though?"
      else say "I just really can't understand you. I'm just going to assume they're OK."
        return false
      end
      return ask_to_feed_now(ask_phrase)
    end
  end
    
### Cameras ###

  listen_for /test camera/i do
    object = SiriAddViews.new
    object.make_root(last_ref_id)

    answer = SiriAnswer.new("Answer", [
      SiriAnswerLine.new("Text Here")
    ])
    
    object.views << SiriAnswerSnippet.new([answer])
    send_object object

    request_completed
   end


  def get_show_camera_object(port)
    object = SiriAddViews.new
    object.make_root(last_ref_id)

    # lines = []
    # lines << SiriAnswerLine.new('Camera',"home.andrewclink.com:#{port}/?action=stream")
    # answer = SiriAnswer.new("Food Camera", lines)
    # object.views << SiriAnswerSnippet.new([answer])
    object.views << SiriAnswerLine.new('Camera',"home.andrewclink.com:#{port}/?action=stream")
    return object  
  end

  listen_for(/show camera/i) do
    send_object get_show_camera_object(1235)
    request_completed
  end

  listen_for(/could I see the(?: cat\'?s)? food(?: bowl)?(?: please)?/i) do
    send_object get_show_camera_object(1235)
    request_completed
  end

  listen_for(/show me(?: the)?(?: cat\'?s)? food(?: bowl)?/i) do
    show_camera(1235)
    request_completed
  end
      
end
