require 'readline'
require 'yaml'

class SiriProxy::Console
  
  include SiriProxy::Logging
  
  attr_accessor :plugin_manager
  
  def initialize
    # Load Logger
    SiriProxy::logger = SiriProxy::Logger.new($STDOUT)

    # Create a plugin manager
    self.plugin_manager = SiriProxy::PluginManager.new
    
    # Load Readline history
    hist = YAML::load_file(File.expand_path("~/.siriproxy_history"))
    hist.each do |line|
      Readline::HISTORY.push line
    end
    
    log "Console Initialized"
  end
  
  def handle_command(cmd)
    case cmd
    when "exit", "quit"
      console_exit
    else
      plugin_manager.process(cmd)
    end
  end
  
  def console_exit
    Readline::HISTORY.pop if Readline::HISTORY[Readline::HISTORY.length-1] =~ /exit|quit/

    File.open(File.expand_path("~/.siriproxy_history"), "a") do |f|
      f.write Readline::HISTORY.to_a.to_yaml
    end
    
    exit(0)
  end

  def run
    swizzle_plugin_manager
    swizzle_plugin_class

    prompt = ">> " #Color::Red + ">> " + Color::Reset# + Color::Bold

    begin
      while cmd = Readline.readline(prompt, true) do
        print Color::Reset
        cmd.chomp!
        handle_command(cmd)
      end
    rescue Interrupt
      console_exit
    end
  end
  

  ##@TODO write a console-friendly subclass instead
  def swizzle_plugin_manager
    # this is ugly, but works for now
    SiriProxy::PluginManager.class_eval do
      def respond(text, options={})
        object = generate_siri_utterance("ref_id", 
                                          text, 
                                          (options[:spoken] or text), 
                                          options[:prompt_for_response] == true)
        log Color::Green + "=>#{text}" + Color::Reset
        pp object.to_hash if SiriProxy::config.log_level >= 2
      end
      def process(text)
        begin
          result = super(text)
        rescue Exception => e
          log :error, "Exception: #{e.inspect}"
          log 1, "Backtrace: #{e.backtrace.join("\n")}"
          return "Exception: #{e.inspect}"
        end

        result 
      end

      def send_request_complete_to_iphone
        log "-> Request Complete"
      end

      def no_matches
        log :error, "No plugin responded"
      end

    end
  end
  
  
  def swizzle_plugin_class
    SiriProxy::Plugin.class_eval do
      def last_ref_id
        0
      end

      def send_object(object, options={:target => :iphone})
        if object.is_a?(String)
          log 2, "=> #{object}"
        else
          pp object.to_hash if SiriProxy::config.log_level >= 2
        end
          
      end
    end
  end
  

    
end