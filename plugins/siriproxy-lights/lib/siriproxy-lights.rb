require 'cora'
require 'siri_objects'
require 'pp'
require 'socket'

require 'fileutils'
require 'rubygems'
require 'ftdi'
require 'cronedit'

require 'dimmer'

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
    initialize_dimmer
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

  AVAILABLE_DIMMERS = "(desk|bed ?room)? ?(lamp|lights|light)"

  def initialize_dimmer
    dev = DimmerDevice.new
    if dev
      dev.open
      @desk_lamp      = dev.dimmers[0]
      @bedroom_lights = dev.dimmers[1]
    end
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

  # # # #

  listen_for /test lights/i do
    say "Lights available, context: #{@ftdi}"
    request_completed
  end
  
  # # # # 
  
  listen_for(/how high (?:are|is) (?:the|my|our) #{AVAILABLE_DIMMERS}/i) do |place, thing|
    value = dimmer_for(place).value
    value = value.to_f / 255.0 * 100
    value = value.round
    
    say "#{value}%"
    request_completed
  end
  
  listen_for(/set (?:my|the|our) #{AVAILABLE_DIMMERS} to (\d+)%/i) do |place, thing, percentage|
    dimmer = dimmer_for(place)
    
    puts "Percentage: #{percentage.inspect}"
    value = percentage.to_i / 100.0 * 255.0
    
    dimmer.fade(:value => value.round, :duration => 120)
    
    say "Fading the #{place} #{thing} to #{percentage}%"
    request_completed
  end
  
  listen_for(/dim (?:the|my|our) #{AVAILABLE_DIMMERS}/) do |place, thing|
    dimmer = dimmer_for(place)
    if dimmer.value < 5
      say "The #{place} lights are already down all the way."
      request_completed
      return
    end
    
    infer_dim_for dimmer_for(place)

    say "Ok, turning #{thing =~ /s$/ ? "them" : "it"} down a bit"
    request_completed
  end
  
  listen_for(/(?:bring|fade)(?: up)? (?:the|my|our) #{AVAILABLE_DIMMERS}(?: up)? ?(all the way|a little|a bit)?/) do |place, thing, amount|
    dimmer = dimmer_for(place)
    
    if dimmer.value >= 255
      say "The #{place} lights are already at 100%"
      request_completed
      return
    end

    value = case amount
    when /all/ then 255
    when /little|bit/ then dimmer.value + 10
    else dimmer.value + 25
    end

    dimmer.fade(:value => value, :duration => 120) # 1 second
    
    say "Ok, turning #{thing =~ /s$/ ? "them" : "it"} up a bit"
    request_completed
  end
  
  def dimmer_for(place)
    dimmer = case place
    when "desk" then @desk_lamp
    when /bed ?room/ then @bedroom_lights
    else @bedroom_lights
    end
  end

  def infer_dim_for(dimmer)
    target_value = case Time.now.hour
    when 0..6    then 75
    when 7..9    then 100
    when 10..16  then 150
    when 17..18  then 110
    when 19      then 90
    when 20      then 80
    when 21..24  then 60
    else 128
    end
    
    puts "Target value: #{target_value}"
    
    if target_value <= dimmer.value
      target_value = dimmer.value - 10
    end
    
    dimmer.fade(:value => target_value, :duration => 240) # 2 seconds
  end
  
  # # # #

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
  
    
  listen_for(/when will the lights turn (on|off)/i) do |state|
    jobs = Crontab.List()
    job_def  = jobs["lights_alarm_#{state}"]


    begin
       entry = CronEntry.new(job_def).to_hash
    rescue
      say "The lights aren't scheduled to turn #{state}."
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
    
    say "The lights will be turned #{state} at #{time}."
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

  listen_for(/turn the(bedroom)? lights? (on|off)/i) do |where, state|
    handle_lights(state, where)
  end

  listen_for(/blink the lights?/i) do
    say "Blinking!"
    request_completed

    fork do
      10.times do 
        @ftdi.write_data([0xff])
        sleep(0.5)
        @ftdi.write_data([0x00])
        sleep(0.25)
      end
    end
  end
  

  # Other useful stuff that I haven't properly dealt with

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
  

end