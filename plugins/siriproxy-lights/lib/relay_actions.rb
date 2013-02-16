module RelayActions

  def handle_relay(state, where)
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
end
