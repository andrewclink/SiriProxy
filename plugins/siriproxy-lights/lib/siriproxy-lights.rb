require 'cora'
require 'siri_objects'
require 'pp'
require 'socket'

require 'fileutils'
require 'rubygems'
require 'ftdi'
require 'cronedit'

require 'dimmer' # Dimmer driver
require 'dimmer_actions'
require 'scheduling'
require 'relay_actions'


#######
# This plugin interfaces between Siri and a USB device to control mains voltages. It can use either an
# FTDI serial device to bit-bang relays on and off, or a dimmer board that implements digital phase-angle 
# shifts based on an ATMega8u2 (to my knowledge only one of which exists).
#
# The FTDI solution simply connects the electromagnet of a relay to one of the bit bang channels. If your
# relay cannot close with five volts, a transistor and higher voltage (say, 12v) source would be needed. 
#
# A quick word if you haven't a ton of experience with clunky, slow relays, an electromagnet is essentially
# a dead short; use a resistor to limit the current allowed through the coil so that the voltage does 
# not drop. Your USB bus normally won't have much trouble with 100mA at 5v, so if you can't get the relay 
# to open with a 50Ω series resistor, you'll need to use a transistor to a higher-voltage source.
#
# Work is ongoing to clean up the API and release the schematics and source code for the dimmer board.
# Essentially, it uses a zero-cross detector to vary the phase angle at which a triac is triggered. Mine
# currently has 2 channels. Although the firmware supports more, USB communication causes the second channel
# to flicker momentarily, presumably because the triac is triggered late.
#
#
# No license because Christ would forgive rather than sue anyway.
# Andrew Clink, Feb 2013
######

class SiriProxy::Plugin::Lights < SiriProxy::Plugin
  include RelayActions
  include DimmerActions
  include Scheduling

  include CronEdit

  def initialize(config)
    @last_command = nil

    initialize_ftdi
    initialize_dimmer
  end

  def initialize_ftdi
    log 2, "Initializing FTDI"
    begin
      @ftdi = Ftdi::Context.new
      @ftdi.usb_open(0x0403, 0x6001)
      @ftdi.set_bitmode(0xff, :bitbang)

      @ftdi.read_data_chunksize= 1
    rescue Ftdi::StatusCodeError => e
      log :error, "Could not initialize FTDI context #{e.inspect}"
    end

    #ctx.set_bitmode(0xff, :reset)                                                                                                                                       
    #ctx.usb_close                 
  end

  AVAILABLE_DIMMERS = '(all|[\w\d][\w\d\ ]*)'

  def initialize_dimmer
    log 2, "Initializing Dimmer Device"

    @dimmer_dev = DimmerDevice.new

    unless @dimmer_dev.open
      log :error, "Could not locate dimmer device"
    end
  end
  
  #pragma mark - Accessors
  
  def last_command
    @last_command
  end
  
  
  def last_command=(cmd_struct)
    log 2, "Setting last command: #{cmd_struct.inspect}"
    
    @last_command = cmd_struct
    manager.set_priority_plugin(self)
  end

  #pragma mark - Lights

  listen_for /test lights/i do
    response = "Lights available: "
    response << dimmer_names.collect(&:first).join("+ ")
    say "Lights available: desk lamp, bedroom lights."
    request_completed
  end

  # # # # 
  
  listen_for(/how many lights are there/i) do
    count = @dimmer_dev.dimmer_count
    say "#{count} dimmer#{count == 0 || count > 1 ? "s" : ""} total"
    request_completed
  end

  listen_for(/dimmer(?: number)? (.+?) is(?: also)?(?: for|called)? ?(?:the|my|our)? ([\w\d][\w\d\ ]+?)$/i) do |index, name|
    i = word_to_integer(index)
    
    add_dimmer_name(i, name)
    
    say "Ok, got it, #{name} refers to dimmer number #{i}"
    request_completed
  end

  listen_for(/what index is the dimmer for ([\w\d\ ]+)[\ \?]?/) do |place|
    dimmer = dimmer_for(place)
    
    if dimmer.nil?
      say "I don't know about a dimmer refered to by #{place.strip}"
    else
      say "#{place.strip} has a dimmer on #{dimmer.index}"
    end

    request_completed
  end
  

  # # # #
  
  listen_for(/a little more/i) do
    log 2, "Last Command: #{self.last_command.inspect}"
    command = self.last_command.command rescue nil

    case command
    when :dim then
      say "Dimming a bit more"
      infer_dim_for self.last_command.dimmers
    when :undim then
      say "Raising them a bit more"
      infer_undim_for self.last_command.dimmers
    else
      say "A little more what?"
    end      

    request_completed
  end
  
  
  # # # #

  listen_for(/how high (?:are|is) (?:the|my|our)? ?#{AVAILABLE_DIMMERS}/i) do |place, thing|

    add_views = SiriAddViews.new
    add_views.make_root(last_ref_id)
  
    dimmers_for(place).each do |dimmer|
      value = (dimmer.value.to_f / 255.0 * 100.0).round
      utterance = SiriAssistantUtteranceView.new("Lamp #{dimmer.index} is at #{value}%")
      add_views.views << utterance
    end
  
    send_object add_views
    request_completed
  end

  listen_for(/(?:set|fade|turn) (?:my|the|our)? ?#{AVAILABLE_DIMMERS} to (?:the )?(\d+|max|maximum|min|minimum)%?/i) do |place, percentage|
    value = case percentage
    when /\d+/ then
      value = percentage.to_i / 100.0 * 255.0
    when /max/i then
      value = 255
      percentage = "100%"
    when /min/i then
      value = 0
      percentage = "0%"
    else 0
    end
    log 2, "Percentage: #{percentage.inspect} -> value"
  
    
    dimmers = dimmers_for(place)
    if (dimmers.length > 1)
      say "Fading them to #{percentage}%"
    else
      say "Fading the #{place} to #{percentage}%"
    end
    request_completed
    
    
    dimmers.fade(:value => value.round, :duration => 360) # 3 seconds

    ## Set state for "a little more"
    original_value= dimmers.average_value
    self.last_command = OpenStruct.new({:dimmers => dimmers, :command => (value > original_value ? :undim : :dim)})

    true
  end


  listen_for(/dim (?:the|my|our)? ?#{AVAILABLE_DIMMERS}/i) do |place|
    dimmers = dimmers_for(place)
  
    # Single Dimmer
    #
    if dimmers.all?(&:nil?) || dimmers.length < 1
      say "#{place}? I've never heard of it."
      self.last_command = nil
      request_completed
      
    elsif dimmers.length == 1
      if dimmers[0].value < 5
        say "The #{place} lights are already down all the way."
        request_completed
        self.last_command = nil
      else
        say "Ok, turning #{place =~ /s$/ ? "them" : "it"} down a bit"
        request_completed

        infer_dim_for dimmers
        self.last_command = OpenStruct.new({:dimmers => dimmers, :command => :dim})
      end

    else
      # Multiple dimmers
      #
      say "Setting the mood"
      request_completed
      
      infer_dim_for dimmers

      self.last_command = OpenStruct.new({:dimmers => dimmers, :command => :dim})
    end
  end


  listen_for(/(?:raise|bring|fade)(?: up)? (?:the|my|our)? ?#{AVAILABLE_DIMMERS}(?: up)? ?(all the way|a little|a bit)?/i) do |place, thing, amount|
    dimmers = dimmers_for(place)
  
    completed = false

    if dimmers.length == 1
      if dimmers[0].value >= 255
        say "The #{place} lights are already at 100%"
        self.last_command = nil
        completed = true
      end
    end

    unless completed
      dimmers.each do | dimmer |
        value = case amount
        when /all/ then 255
        when /little|bit/ then dimmer.value + 10
        else dimmer.value + 25
        end

        dimmer.fade(:value => value, :duration => 120) # 1 second
      end
  
      say "Ok, turning #{thing =~ /s$/ ? "them" : "it"} up a bit"

      self.last_command = OpenStruct.new({:dimmers => dimmers, :command => :undim})
      
    end

    request_completed
  end

  # # # #

  listen_for (/test turn (on|off) (?:the|my|our) ?#{AVAILABLE_DIMMERS} at ([1-9]|1[0-2])\:(\d\d)?/i) do |state, where, hour, minute|
    schedule_lights(hour, minute, 0, state)
  end


  listen_for (/turn (on|off) (?:the|my|our) ?#{AVAILABLE_DIMMERS} at ([1-9]|1[0-2])\:(\d\d)?/i) do |state, where, hour, minute|
    dimmers_for(where).each do |dimmer|
      schedule_lights(hour, minute, dimmer.index, state)
    end
  end

  listen_for (/turn (?:the|my|our) ?#{AVAILABLE_DIMMERS} (on|off) at ([1-9]|1[0-2])\:(\d\d)?/i) do |where, state, hour, minute|
    dimmers_for(where).each do |dimmer|
      schedule_lights(hour, minute, dimmer.index, state)
    end
  end

  # # # #
  listen_for(/turn (on|off) (?:the|my|our) ?#{AVAILABLE_DIMMERS} in (\d+|\w+) minutes/i) do |state, place, delta|
    time = Time.now + (word_to_integer(delta) * 60)

    dimmers_for(place).each do |dimmer|
      schedule_lights(time.hour, time.min, dimmer.index, state)
    end

  end

  listen_for(/turn (?:the|my|our) ?#{AVAILABLE_DIMMERS} (on|off) in (\d+|\w+) minutes/i) do |place, state, delta|
    time = Time.now + (word_to_integer(delta) * 60)

    dimmers_for(place).each do |dimmer|
      schedule_lights(time.hour, time.min, dimmer.index, state)
    end

  end

  # # # #

  listen_for(/don't turn the lights (on|off)/i) do |state|
    job_name = "lights_alarm_1_#{state}"
    Crontab.Remove(job_name) rescue nil
    say "Ok, I won't turn the lights #{state}"
    request_completed
  end

  listen_for(/don't turn (on|off) the lights/i) do |state|
    job_name = "lights_alarm_1_#{state}"
    Crontab.Remove(job_name) rescue nil
    say "Ok, I won't be turning #{state} the lights"
    request_completed
  end


  ## Not likely to happen, but possible and worked fine before multiple channels. ##
  # listen_for /turn the lights on at (\w+)\s*(\w+)?\s*(am|pm)?/i do |hour, minute_or_period, period|
  #   schedule_lights(hour, minute_or_period, period)
  # end
  # 
  # listen_for /turn on the lights at (\w+)\s*(\w+)?\s*(am|pm)?/i do |hour, minute_or_period, period|
  #   schedule_lights(hour, minute_or_period, period)
  # end
  #######################################################

  
  listen_for(/when will (?:the|my|our) ?#{AVAILABLE_DIMMERS} turn (on|off)/i) do |where, state|
    jobs = Crontab.List()
    
    dimmer = dimmer_for(where)
    job_def  = jobs[job_name_for(dimmer.index, state)]

    
    entry = nil
    begin
       entry = CronEntry.new(job_def).to_hash
    rescue
      say "The lights aren't scheduled to turn #{state}."
    end
    
    ###
    # Convert time from 24 to 12 hour & determine the period
    unless entry.nil?
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
    end

    request_completed
  end





  






  # ====================================
  # = Boolean On/Off - Lowest Priority =
  # ====================================
  
  listen_for(/turn (on|off) (?:my|the|our) ?#{AVAILABLE_DIMMERS}/i) do |state, where|
    handle_lights(state, where)
  end

  listen_for(/turn (?:my|the|our) ?#{AVAILABLE_DIMMERS} (on|off)/i) do |where, state|
    handle_lights(state, where)
  end

  listen_for(/turn (on|off) all the lights?/i) do |state|
    handle_lights(state, "all")
  end
  listen_for(/turn all the lights? (on|off)/i) do |state|
    handle_lights(state, "all")
  end

  # Are the x lights on?
  listen_for(/(?:are|is) (?:the|my|our)? ?#{AVAILABLE_DIMMERS} (on|off)/i) do |where, state|
    dimmer = dimmer_for(where)

    if dimmer.nil?
      say "I don't know about #{where}"
    else
      
      if dimmer.state == :faded
        say "The #{where} #{where[-1]=='s' ? 'are' : 'is'} at #{dimmer.percentage}%"
      else        
        is_on  = dimmer.state == :on
        negate = state == 'off'
        say "#{negate ? (is_on ? 'No' : 'Yes') : (is_on ? 'Yes' : 'No')}, the #{where} #{where[-1]=='s' ? 'are' : 'is'} #{is_on ? 'on' : 'off'}"
      end
    end

    request_completed
  end


  listen_for /RELAY (?:are the|is the)( bedroom)? lights? (on|off)/i do |where, state|
    current = @ftdi.read_pins

    printf "Pins currently: 0x%x; will test for 0x%x & 0x%x == 0x%x\n", current, current, 0xff, current & 0xff
  
    where = 'bedroom' if where.nil?

    mask = case where
      when 'bedroom' then 0xff
      else 0xff
    end
    is_on = (current & mask) == 0 ? false : true

    log 3,   "mask: #{mask}; is_on: #{is_on}"
    printf "The lights are %s\n", is_on ? "On" : "Off"

    negate = state == 'off'
    printf("Negating? %s\n", negate ? "Yes" : "No");
    say "#{negate ? (is_on ? 'No' : 'Yes') : (is_on ? 'Yes' : 'No')}, the #{where} lights are #{is_on ? 'on' : 'off'}"
    request_completed
  end
  
  
  ####


  listen_for(/blink the lights?/i) do
    say "Blinking!"

    fork do
      10.times do 
        @ftdi.write_data([0xff])
        sleep(0.5)
        @ftdi.write_data([0x00])
        sleep(0.25)
      end
    end

    request_completed
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
