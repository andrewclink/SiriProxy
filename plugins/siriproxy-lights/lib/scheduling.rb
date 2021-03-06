require 'cronedit'

module Scheduling
  include CronEdit
  
  def schedule_fade_on_duration
    30 * 60
  end

  def schedule_fade_off_duration
    20 * 60
  end

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

  def parse_time(hour, minute, period="am")
    now = Time.now
    h = word_to_integer(hour) + (period =~ /pm/ ? 12 : 0)
    m = word_to_integer(minute)
    puts "Hour #{h} Minute: #{m}"
    Time.new now.year, now.month, now.day, h, m
  end
  
  def job_name_for(index, state)
    "lights_alarm_#{index}_#{state}"
  end

  def schedule_lights(hour, minute, dimmer_index, onoff="on")
  
    ## Parse time.
    time = parse_time(hour, minute)
  
    log 2, "Parsed Time: #{time}"
  
    ## Infer period (am/pm)
    while time <= Time.now do
      time = time + (12 * 3600) #Add 12 hours
      log 2, "Time is in past, adding 12hrs"
      log 2, "-> Time is now #{time}"
    end
  
    # schedule
    command  = nil
    call_before = 0

    if false
      job_name = "lights_alarm_#{onoff}"
      command = "/usr/local/rvm/bin/ruby-1.9.3-p374@SiriProxy /home/andrew/Software/lights/lights #{onoff}"
    else
    
      call_before  = (onoff == "on" ? schedule_fade_on_duration : schedule_fade_off_duration) - (5 * 60) # Overlap by 5 minutes
    
      args =  []
      args << "/usr/local/rvm/bin/ruby-1.9.3-p374@SiriProxy"
      args << "/usr/local/siriproxy/plugins/siriproxy-lights/bin/dim"
      args << "fade"
      args << dimmer_index
      args << (onoff == "on" ? 255 : 0)   # Value
      args << call_before * 120 # Units are 120Hz ticks
    
      command = args.collect(&:to_s).join(" ")
    end

    log 2, "Subtracting call ahead time (#{call_before})"
    finish_time = time
    time = time - call_before 
    time += Time.now - time if time < Time.now
    log 2, "-> Time is now #{time}"

    job_name = job_name_for(dimmer_index, onoff)
    Crontab.Remove(job_name) rescue nil
    Crontab.Add  job_name, {:minute=>time.min, :hour=>time.hour, :command=>command}
  
    say "Ok, I'll turn #{onoff} the lights at #{finish_time.strftime("%I:%M %P")}, #{distance_of_time_in_words(Time.now, finish_time)} from now."
    request_completed
  end
end
