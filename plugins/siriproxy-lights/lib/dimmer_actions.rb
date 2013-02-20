require 'yaml'

module DimmerActions

  attr :dimmer_names
  
  def dimmer_names
    load_dimmer_names if @dimmer_names.nil?
    @dimmer_names
  end
    
  ## Dimmer Naming File Management
  
  def dimmer_name_path
    File.join(File.dirname(__FILE__), "..", "config", "dimmers.yml")
  end
  
  def load_dimmer_names
    if File.exists?(dimmer_name_path)
      @dimmer_names = YAML::load_file(dimmer_name_path)
    else
      @dimmer_names = []
    end
  end
  
  def dimmer_names_did_change
    File.open(dimmer_name_path, "w") do |f|
      f.write(dimmer_names.to_yaml)
    end
  end
  
  ## Adding dimmers
  
  def add_dimmer_name(index, name)
    dimmer_names[index] ||= []
    
    exp = name.strip.gsub(/ (lights?|lamps?)s?/, " (?:lights?|lamps?)?").gsub(/\s+/, " ?")
    reg = Regexp.new(exp, Regexp::IGNORECASE)
    
    if dimmer_names[index].detect {|x| x == reg }.nil?
      dimmer_names[index] << reg
    
      dimmer_names_did_change
    end

    name
  end
  
  ## Retreiving dimmers

  def dimmer_for(place)

    puts "Finding dimmer for #{place}"

    index = nil
    
    puts "dimmer_names: #{dimmer_names.inspect}"
    
    i = 0
    dimmer_names.each do |names|
      puts "-> Checking #{i}"
      unless names.detect {|n| n =~ place }.nil?
        index = i
        break
      end
      i += 1
    end
    
    dimmer = unless index.nil?
      @dimmer_dev.dimmers[index]
    else
      nil
    end

    puts "-> Dimmer for #{place} is ##{index}: #{dimmer}"
    dimmer
  end

  def dimmers_for(place)
  
    dimmers = DimmerCollection.new

    return @dimmer_dev.dimmers if place =~ /all/i

    i=0
    dimmer_names.each do |names|
      puts "-> Checking #{i}"
      dimmers << @dimmer_dev.dimmers[i] unless names.detect {|n| n =~ place }.nil?
      i += 1
    end

    dimmers
  end

  def infer_dim_for(dimmers)
    
    return if dimmers.nil?
    
    target_value = case Time.now.hour
    when 0..6    then 95
    when 7..9    then 110
    when 10..16  then 180
    when 17..18  then 170
    when 19      then 128
    when 20      then 110
    when 21..24  then 90
    else 128
    end
  
    puts "Target value: #{target_value}"
  
    if dimmers.is_a?(Dimmer)
      dimmers = DimmerCollection.new(dimmers)
    end

    _target_value = 0
    dimmers.each do |dimmer|
      _target_value = target_value
      if _target_value >= dimmer.value
        _target_value = dimmer.average_value - 10
        puts "Target value too high; adjusting downward: #{target_value}"
      end
      
      dimmer.fade(:value => _target_value, :duration => 360) # 3 seconds
    end

  end
  
  def infer_undim_for(dimmers)
    dimmers.fade(:value => dimmers.value + 25, :duration => 120)
  end
  
  def handle_lights(state=:on, where)
    dimmers = dimmers_for(where)

    if dimmers.length < 1
      say "I don't know about #{where} lights"
      request_completed
      return
    end
    
    puts "Requested: #{state.inspect}"
    state   = case state
    when :on  then :on
    when /on/ then :on
    else :off
    end
    
    puts "    State: #{state.inspect}"

    # dimmers.each do |dimmer|
    #   current = dimmer.state
    # 
    #   if (state == :on  && current == :on) ||
    #      (state == :off && current == :off)
    #    
    #      say "The #{name} lights are already #{state}"
    # end
      
    
    # dimmer.value = (onoff == "on" ? 255 : 0)
    dimmers.fade(:value => (state == :on ? 255 : 0),
                 :duration => 240)
    
    say "Lights #{state}"
    request_completed
      
  end

end
