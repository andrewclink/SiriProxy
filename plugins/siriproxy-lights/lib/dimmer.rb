require 'libusb'

DEV_VENDOR = 0x03eb

DIMMER_CMD_COUNT  = 1
DIMMER_CMD_GET    = 2
DIMMER_CMD_SET    = 3
DIMMER_CMD_FADE   = 4

class DimmerDevice
  
  include LIBUSB
  
  def initialize
    @c = LIBUSB::Context.new
  end
  
  def open
    @dev = @c.devices(:idVendor=> DEV_VENDOR).first
    
    if @dev.nil?
      puts "Could not find Dimmer device."
      return
    end
    
    print @dev.inspect
    print "\n"
    @dev.interfaces.each {|i| printf("\t-> #{i.inspect}\n")}
    
    @handle = @dev.open
    # @handle.detach_kernel_driver(0)

    begin
      # @handle.claim_interface(0)
    rescue LIBUSB::ERROR_BUSY => e
      puts "Device was busy"
    end
    
  end
  
  def close
    @handle.release_interface(0)    rescue nil
    @handle.attach_kernel_driver(0) rescue nil
    @handle.close
  end
  
  def dimmer_count
    if @dimmer_count.nil?
      begin
        val, len, err = @handle.control_transfer(:bmRequestType => ENDPOINT_IN | REQUEST_TYPE_CLASS | RECIPIENT_DEVICE, 
                                                 :bRequest => DIMMER_CMD_COUNT, 
                                                 :wValue => 0x0, 
                                                 :wIndex => 0x0000, 
                                                 :dataIn => 2)
        # puts "Val: #{val.inspect}"
        # puts "Len: #{len.inspect}"
        # puts "Err: #{err.inspect}"
      rescue Exception => e
        puts "Exception: #{e.inspect}"
        return 0
      end
      
      @dimmer_count = val.unpack("S")[0]
    end

    return @dimmer_count
  end
  
  def dimmers
    if @dimmers.nil?
      @dimmers = dimmer_count.times.collect do |i|
        d = Dimmer.new
        d.device = self
        d.index = i
        d
      end
    end
    
    @dimmers
  end
  
  def dimmer_value(index)
    begin
      raise ArgumentError.new("Index beyond bounds") if (index > dimmer_count)

      val, len, err = @handle.control_transfer(:bmRequestType => ENDPOINT_IN | REQUEST_TYPE_CLASS | RECIPIENT_DEVICE, 
                                               :bRequest => DIMMER_CMD_GET, 
                                               :wValue => 0x0, 
                                               :wIndex => index, 
                                               :dataIn => 2)
    rescue Exception => e
      puts "Exception: #{e.inspect}"
      return -1
    end
    
    val.unpack("S")[0]
  end
  

  def set_dimmer_value(index, value)
    
    if value > 255
      value = 255
    end
    
    begin
      raise ArgumentError.new("Index beyond bounds") if (index > dimmer_count)
      
      val, len, err = @handle.control_transfer(:bmRequestType => ENDPOINT_OUT | REQUEST_TYPE_CLASS | RECIPIENT_DEVICE, 
                                               :bRequest => DIMMER_CMD_SET, 
                                               :wValue => value,
                                               :wIndex => index)
    rescue Exception => e
      puts "Exception: #{e.inspect}"
      return false
    end
    
    true
  end

  
  def fade_dimmer(index, value, duration)
    
      if value > 255
      value = 255
    end

    begin
      raise ArgumentError.new("Index beyond bounds") if (index > dimmer_count)

      val, len, err = @handle.control_transfer(:bmRequestType => ENDPOINT_OUT | REQUEST_TYPE_CLASS | RECIPIENT_DEVICE, 
                                               :bRequest => DIMMER_CMD_FADE, 
                                               :wValue => value,
                                               :wIndex => index,
                                               :dataOut => [duration].pack("S"))
    rescue Exception => e
      puts "Exception: #{e.inspect}"
      return false
    end
    
    true
  end
  
end

class Dimmer
  
  attr_accessor :index
  attr_accessor :device
  attr_accessor :value
  
  def value
    device.dimmer_value(index)
  end
  
  def value=(value)
    device.set_dimmer_value(index, value)
  end
  
  def fade(args={})
    val = args[:value]
    dur = args[:duration]
    
    device.fade_dimmer(index, val, dur)
  end
  
  def state
    current = nil
    if self.value > 200
      current = :on
    elsif self.value < 100
      current = :off
    else
      current = :faded
    end
    
    current
  end
  
  
  def to_s
    "#<#{self.class}:#{index} value=#{value}>"
  end
end


class DimmerCollection < Array

  ## Returns average value
  def value
    self.inject{|sum, dimmer| sum + dimmer.value }.to_f / self.count
  end

  ## Attempts to return an array of return values
  def method_missing(method, *args)
    return super(method, *args) unless Dimmer.instance_methods.include?(method)
    
    puts "Applying #{method.inspect} to dimmers: #{self}"
    self.collect do |dimmer|
      dimmer && dimmer.send(method, *args)
    end
  end
  
end

