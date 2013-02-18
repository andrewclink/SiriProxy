require 'cronedit'

module Scheduling
  include CronEdit

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
  
  def job_name_for(index, state)
    "lights_alarm_#{index}_#{onoff}"
  end

  def schedule_lights(hour, minute, dimmer_index, onoff="on")
  
    ## Parse time.
    time = parse_time(hour, minute)
  
    ## Infer period (am/pm)
    while time <= Time.now do
      time = time + (12 * 3600) #Add 12 hours
    end
  
    # schedule
    command  = nil
    call_before = 0

    if false
      job_name = "lights_alarm_#{onoff}"
      command = "/usr/local/rvm/bin/ruby-1.9.3-p374@SiriProxy /home/andrew/Software/lights/lights #{onoff}"
    else
    
      dimmer_index = 1
      call_before  = (onoff == "on" ? 9 : 5)
    
      args =  []
      args << "/usr/local/rvm/bin/ruby-1.9.3-p374@SiriProxy"
      args << "/usr/local/siriproxy/plugins/siriproxy-lights/bin/dim"
      args << "fade"
      args << dimmer_index
      args << (onoff == "on" ? 255 : 0)   # Value
      args << (onoff == "on" ? 120 * 60 * 9 : 120 * 60 * 5) # duration 9min : 5min
    
      command = args.collect(&:to_s).join(" ")
    end

    time = time - (call_before * 60)

    job_name = job_name_for(dimmer_index, state)
    Crontab.Remove(job_name) rescue nil
    Crontab.Add  job_name, {:minute=>time.min, :hour=>time.hour, :command=>command}
  
    say "Ok, I'll turn #{onoff} the lights at #{time.strftime("%I:%M %P")}, #{distance_of_time_in_words(Time.now, time)} from now."
    request_completed
  end
end
