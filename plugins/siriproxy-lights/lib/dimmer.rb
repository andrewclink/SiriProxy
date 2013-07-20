require 'libusb'

DEV_VENDOR_ID     = 0x6666 #Prototype Vendor ID
DEV_DEVICE_ID     = 0xd144 #Dimm

DIMMER_CMD_COUNT  = 0x21
DIMMER_CMD_GET    = 0x22
DIMMER_CMD_SET    = 0x23
DIMMER_CMD_FADE   = 0x24

class DimmerDevice
  
  include LIBUSB
  
  def initialize
    @c = LIBUSB::Context.new
    self
  end
  
  def open
    @dev = @c.devices(:idVendor=> DEV_VENDOR_ID,
                      :idProduct => DEV_DEVICE_ID).first
    
    if @dev.nil?
      #puts "Could not find Dimmer device."
      return false
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
    
    true
  end
  
  def close
    @handle.release_interface(0)    rescue nil
    @handle.attach_kernel_driver(0) rescue nil
    @handle.close
  end
  
  def dimmer_count
    if @dimmer_count.nil?
      begin
        val, len, err = @handle.control_transfer(:bmRequestType => ENDPOINT_IN | REQUEST_TYPE_VENDOR | RECIPIENT_DEVICE, 
                                                 :bRequest => DIMMER_CMD_COUNT, 
                                                 :wValue => 0x0, 
                                                 :wIndex => 0x0000, 
                                                 :dataIn => 2)
        # puts "Val: #{val.inspect}"
        # puts "Len: #{len.inspect}"
        # puts "Err: #{err.inspect}"
      rescue Exception => e
        puts "dimmer_count failed with exception: #{e.inspect}"
        raise e
        return 0
      end
      
      @dimmer_count = val.unpack("S")[0]
    end

    return @dimmer_count
  end
  
  def dimmers
    if @dimmers.nil?
      @dimmers = DimmerCollection.new
      dimmer_count.times do |i|
        d = Dimmer.new
        d.device = self
        d.index = i
        @dimmers << d
      end
    end
    
    @dimmers
  end
  
  def dimmer_value(index)
    raise ArgumentError.new("Index beyond bounds") if (index > dimmer_count)

    begin
      val, len, err = @handle.control_transfer(:bmRequestType => ENDPOINT_IN | REQUEST_TYPE_VENDOR | RECIPIENT_DEVICE, 
                                               :bRequest => DIMMER_CMD_GET, 
                                               :wValue => 0x0, 
                                               :wIndex => index, 
                                               :dataIn => 2)
    rescue Exception => e
      puts "dimmer_value failed with exception: #{e.inspect}"
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
      
      val, len, err = @handle.control_transfer(:bmRequestType => ENDPOINT_OUT | REQUEST_TYPE_VENDOR | RECIPIENT_DEVICE, 
                                               :bRequest => DIMMER_CMD_SET, 
                                               :wValue => value,
                                               :wIndex => index)
    rescue Exception => e
      puts "set_dimmer_value failed with exception: #{e.inspect}"
      return false
    end
    
    true
  end

  
  # Fade a dimmer.
  # args: 
  #   index: the index of the dimmer to fade
  #   value: the 8-bit brightness of the dimmer
  #   duration: a 32-bit unsigned integer corresponding to 120Hz ticks, of which 24 bits are useful (maximum 38 hour fade)
  #
  def fade_dimmer(index, value, duration)
    
    value = 255 if value > 255
    duration = 0 if duration < 0
    duration = 0x00ffFFFF if duration > 0x00ffFFFF 
    
    begin
      raise ArgumentError.new("Index beyond bounds") if (index > dimmer_count)

      data_out = [duration].pack("L")
      val, len, err = @handle.control_transfer(:bmRequestType => ENDPOINT_OUT | REQUEST_TYPE_VENDOR | RECIPIENT_DEVICE, 
                                               :bRequest => DIMMER_CMD_FADE, 
                                               :wValue => value,
                                               :wIndex => index,
                                               :dataOut => data_out)
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
  
  def percentage
    (value.to_f / 255.0 * 100).round
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
    elsif self.value < 1
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

  def initialize(*args)
    self.concat(args)
  end

  ## Returns average value
  def value
    self.inject(0) {|sum, dimmer| sum + dimmer.value }.to_f / self.count
  end
  
  def values
    self.collect(&:value)
  end

  ## Attempts to return an array of return values
  def method_missing(method, *args)
    return super(method, *args) unless Dimmer.instance_methods.include?(method)
    
#    puts "Applying #{method.inspect} to dimmers: #{self}"
    self.collect do |dimmer|
#      puts "-> dimmer.send(#{method.inspect}, #{args.inspect})"
      dimmer && dimmer.send(method, *args)
    end
  end
  
end

