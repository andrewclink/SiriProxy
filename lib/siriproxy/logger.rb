
class << SiriProxy
  def logger
    @logger
  end

  def logger=(logger)
    @logger=logger
  end
end

module SiriProxy::Logging
  def log(level=1, msg)
    SiriProxy::logger.log(level, msg)
  end
end


class SiriProxy::Logger
  def initialize(path)
    @file_handle = case path
      when STDOUT, STDERR then path
      when String then File.open(path, "a")
      else STDOUT
    end
  end
  
  def out
    @file_handle
  end
  
  def color_for_level(level)
    case level
    when 1,2,3  then Color::Grey
    when :error then Color::Red
    when :warn  then Color::Yellow
    else Color::Default
    end
  end
  
  def log_line_header(level)
    case level
    when 0      then " [Silent]"
    when 1      then " [Info]  "
    when 2      then " [Info]  "
    when 3      then " [Debug] "
    when :warn  then " [Warn]  "
    when :error then " [Error] "
    else        " [DEBUG] "
    end
  end
  
  def log(level=1, str)
    ## This should probably take into account STDERR, etc.
    case level
    when :error,:warn then
      out.puts(color_for_level(level) + log_line_header(level) + str + Color::Reset)
    when Fixnum then
      if SiriProxy::config.log_level >= level
        out.puts(color_for_level(level) + log_line_header(level) + Color::Reset + str)
      end
    else
      out.puts "???"
    end
  end
  
end