require 'cora'
require 'siri_objects'
require 'pp'
require 'socket'

require 'fileutils'
require 'rubygems'
require 'ftdi'
require 'cronedit'

#######
# This is a "hello world" style plugin. It simply intercepts the phrase "test siri proxy" and responds
# with a message about the proxy being up and running (along with a couple other core features). This
# is good base code for other plugins.
#
# Remember to add other plugins to the "config.yml" file if you create them!
######

class SiriProxy::Plugin::Lights < SiriProxy::Plugin
  include CronEdit
  
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

## Scheduling

  def word_to_integer(word)
    result = case word
    when Integer            then word
    when /\d+?/             then word.to_i
    when nil                then 0
    when /o?\'?clock/       then 0
    when /one/i             then 1
    when /two|to|too/       then 2
    when /th|tree/          then 
      word =~ /y$/ ? 30 : 3
    when /four|pour|poor/   then 4
    when /five/             then 5
    when /six|sex|sick/     then 6
    when /se/               then 7
    when /eight|ate/        then 8
    when /nine/             then 9
    when /ten/              then 10
    when /eleven/           then 11
    when /twelve/           then 12
    else 
      0
    end
    puts "-> Converting #{word.inspect} to integer... Got #{result} (to_i: #{word.to_i})"
    return result
  end

  def parse_time(hour, minute, period)
    now = Time.now
    h = word_to_integer(hour) + (period =~ /pm/ ? 12 : 0)
    m = word_to_integer(minute) 
    Time.new now.year, now.month, now.day, h, m
  end

  listen_for /turn (on|off) the lights at ([1-9]|1[0-2])\:(\d\d)?\s*(am|pm)?/i do |state, hour, minute, period|
    schedule_lights(hour, minute, period, state)
  end
  listen_for /turn the lights (on|off) at ([1-9]|1[0-2])\:(\d\d)?\s*(am|pm)?/i do |state, hour, minute, period|
    schedule_lights(hour, minute, period, state)
  end

  # # # #
  listen_for(/turn (on|off) the lights in (\d+|\w+) minutes/i) do |state, delta|
    time = Time.now + (word_to_integer(delta) * 60)
    schedule_lights(time.hour, time.min, "am", state) #passing am because time will be in 24 hour time already.
  end
  listen_for(/turn the lights (on|off) in (\d+|\w+) minutes/i) do |state, delta|
    time = Time.now + (word_to_integer(delta) * 60)
    schedule_lights(time.hour, time.min, "am", state) #passing am because time will be in 24 hour time already.
  end
  
  # # # #
  listen_for(/don't turn the lights (on|off)/i) do |state|
    job_name = "lights_alarm_#{state}"
    Crontab.Remove(job_name)
    say "Ok, I won't turn the lights #{state}"
    request_completed
  end
  
  listen_for(/don't turn (on|off) the lights/i) do |state|
    job_name = "lights_alarm_#{state}"
    Crontab.Remove(job_name)
    say "Ok, I won't be turning #{state} the lights"
    request_completed
  end
  
  
  ## Not likely to happen, but possible and work fine. ##
  listen_for /turn the lights on at (\w+)\s*(\w+)?\s*(am|pm)?/i do |hour, minute_or_period, period|
    schedule_lights(hour, minute_or_period, period)
  end

  listen_for /turn on the lights at (\w+)\s*(\w+)?\s*(am|pm)?/i do |hour, minute_or_period, period|
    schedule_lights(hour, minute_or_period, period)
  end
  #######################################################
  
    
  listen_for %r|when will the lights turn on|i do
    jobs = Crontab.List()
    job_def  = jobs["lights_alarm"]


    begin
       entry = CronEntry.new(job_def).to_hash
    rescue
      say "The lights aren't scheduled to turn on."
      request_completed
      return
    end

    #
    # Convert time from 24 to 12 hour & determine the period
    hour = entry[:hour].to_i
    period = "am"
    if hour == 12
      period = "pm"
    elsif hour == 0
      hour = 12
      period = "am"
    elsif hour > 12
      hour -= 12 
      period = "pm"
    end
    
    time = sprintf("%d:%02d %s", hour, entry[:minute], period)
    
    say "The lights will be turned on at #{time}."
    request_completed
  end
    
  def schedule_lights(hour, minute_or_period, period, onoff="on")
    minute = 0
    if period.nil?
      if minute_or_period =~ /am|pm/
        # Didn't give a minute
        period = minute_or_period
        minute = 0
      else
        # Didn't give a period; must be assumed
        minute = minute_or_period
      end
    else
      # "five thirty am"
      # period is set.
      minute = minute_or_period
    end
    
    ## Parse time.
    time = parse_time(hour, minute, period)
    
    ## Infer period
    if period.nil?
      while time <= Time.now do
        time = time + (12 * 3600) #Add 12 hours
      end
    end
    
    # schedule
    job_name = "lights_alarm_#{onoff}"
    command = "/usr/local/rvm/bin/ruby-1.9.3-p374@SiriProxy /home/andrew/Software/lights/lights #{onoff}"
    Crontab.Remove(job_name) rescue nil
    Crontab.Add  job_name, {:minute=>time.min, :hour=>time.hour, :command=>command}
    
    say "Ok, I'll turn #{onoff} the lights at #{time.strftime("%I:%M %P")}, #{distance_of_time_in_words(Time.now, time)} from now."
    request_completed
  end

  listen_for /test lights/i do
    say "Lights available, context: #{@ftdi}"
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

  listen_for Regexp.new(/blink the lights?/i) do
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
