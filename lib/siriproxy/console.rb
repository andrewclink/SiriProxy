
class SiriProxy::Console
  
  include SiriProxy::Logging
  
  attr_accessor :plugin_manager
  
  def initialize
    SiriProxy::logger = SiriProxy::Logger.new($STDOUT)

    self.plugin_manager = SiriProxy::PluginManager.new
    
    log "Console Initialized"
  end
  
  def handle_command(cmd)
    case cmd
    when "exit", "quit"
      exit
    else
      plugin_manager.process(cmd)
    end
  end

  def run
    swizzle_plugin_manager
    swizzle_plugin_class

    repl = -> prompt do
      print prompt
      cmd = gets.chomp!
      print Color::Reset
      
      handle_command(cmd)
    end

    loop { repl[ Color::Red + ">> " + Color::Reset + Color::Bold] }
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