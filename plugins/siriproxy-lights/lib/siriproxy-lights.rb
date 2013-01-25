require 'cora'
require 'siri_objects'
require 'pp'
require 'socket'

require 'fileutils'
require 'rubygems'
require 'ftdi'

#######
# This is a "hello world" style plugin. It simply intercepts the phrase "test siri proxy" and responds
# with a message about the proxy being up and running (along with a couple other core features). This
# is good base code for other plugins.
#
# Remember to add other plugins to the "config.yml" file if you create them!
######

class SiriProxy::Plugin::Lights < SiriProxy::Plugin
  
  attr_accessor :wants_person, :current_fiber, :firstName, :lastName
  
  def initialize(config)
    #if you have custom configuration options, process them here!
    initialize_ftdi
    
  end

  def initialize_ftdi
    puts "Initializing FTDI"
    begin
      @ftdi = Ftdi::Context.new
      @ftdi.usb_open(0x0403, 0x6001)
      @ftdi.set_bitmode(0xff, :bitbang)

      @ftdi.read_data_chunksize= 1
    rescue Ftdi::StatusCodeError => e
      puts "Could not initialize FTDI context #{e.inspect}"
    end

    #ctx.set_bitmode(0xff, :reset)                                                                                                                                       
    #ctx.usb_close                 
  end

  filter "PersonSearchCompleted" do |object|
    puts "[Info - PersonSearchCompleted] Object:"
    results = object["properties"]["results"]
    if results.length < 1
      puts " -> No Results"
    else
      contact = results[0]["properties"]
      @firstName = contact["firstName"]
      @lastName  = contact["lastName"]
    end
    
    puts "Name: #{@firstName} #{@lastName} (wants_person = #{@wants_person})"
    
    if @wants_person
      manager.callback.call(contact)
      false
    else
      nil
    end
  end
  
  def set_screen_blank(isoff)

    say "Ok, I'll turn the screen #{isoff ? "off" : "on"}"

    if isoff
      fork do 
        exec 'screen-off'
      end
    else
      File.unlink("/tmp/screen-off-lock") rescue nil
    end 
  end

  listen_for /turn (off|on) (?:the )?screen/i do |onoff|
    set_screen_blank(!(onoff =~ /on/i))
    request_completed
  end

  listen_for /turn (?:the )?screen (off|on)/i do |onoff|
    set_screen_blank(!(onoff =~ /on/i))
    request_completed
  end
  
  listen_for /reset (?:the )?fans ?(?:please)/i do
    system('killall fancontrol')
    system('service fancontrol start')
    say "Ok, sorry about the noise!"
    request_completed
  end
  
  listen_for /person/i do
    
    f = Fiber.current
    @current_fiber = f
    @wants_person = true
    
    s = SiriPersonSearch.new("PersonSearch", "com.apple.ace.contact")
    s.properties["me"] = "true"
    # s.properties["name"] = "Alex"
    s.properties["scope"] = "Local"
    s.make_root(last_ref_id)
    
    puts "====== PersonSearch Request ======="
    pp s.to_hash
    puts " "
    
    # manager.respond "Gotcha @{tts#\e\\pause=500\\\e\\rate=90\\} person"

    add_views = SiriAddViews.new
    add_views.temporary = true
    add_views.make_root(last_ref_id)
    utterance = SiriAssistantUtteranceView.new("Gotcha @{tts#\e\\pause=500\\\e\\rate=90\\} person")
    add_views.views << utterance

    #you can also do "send_object object, target: :guzzoni" in order to send an object to guzzoni
    send_object add_views #send_object takes a hash or a SiriObject object


    send_object s, target: :iphone
    manager.set_callback do |text|
      say "Looks like you're #{@firstName} #{@lastName}"
      f.resume(text)
    end

    Fiber.yield

    say "Done"
    request_completed
    
  end

#pragma mark - Lights

  listen_for /test project/i do
    say "Ok, FTDI: #{@ftdi}"
    request_completed
  end

  
  def handle_lights(state, where)
    begin
    data    = (state===true || state == "on") ? 0xff : 0x00
    current = @ftdi.read_pins

    printf("New: 0x%x; old 0x%x; &= 0x%x", data, current, data & current)

    
    if ((data == 0 && current != 0) || 
       (current == 0 && data != 0) || 
       (data & current) != data)

      @ftdi.write_data([data])
      say "Ok, lights #{state}"

    else

      say "The lights are already #{state}"

    end

    rescue Ftdi::StatusCodeError
      say "I can't!"
      initialize_ftdi             
    end

    request_completed
  end

  listen_for /(?:are the|is the)( bedroom)? lights? (on|off)/i do |where, state|
    current = @ftdi.read_pins

    printf "Pins currently: 0x%x; will test for 0x%x & 0x%x == 0x%x\n", current, current, 0xff, current & 0xff
    
    where = 'bedroom' if where.nil?

    mask = case where
      when 'bedroom' then 0xff
      else 0xff
    end
    is_on = (current & mask) == 0 ? false : true

    puts   "mask: #{mask}; is_on: #{is_on}"
    printf "The lights are %s\n", is_on ? "On" : "Off"

    negate = state == 'off'
    printf("Negating? %s\n", negate ? "Yes" : "No");
    say "#{negate ? (is_on ? 'No' : 'Yes') : (is_on ? 'Yes' : 'No')}, the #{where} lights are #{is_on ? 'on' : 'off'}"
    request_completed
  end

  listen_for /turn (on|off) the(bedroom)? light(?:s)?/i do |state, where|
    handle_lights(state, where)
  end

  listen_for /turn the(bedroom)? lights? (on|off)/i do |where, state|
    handle_lights(state, where)
  end

  listen_for /blink the lights?/i do

    say "Blinking!"
    request_completed

    10.times do 
      @ftdi.write_data([0xff])
      sleep(0.5)
      @ftdi.write_data([0x00])
      sleep(0.25)
    end
    
  end
      
end
