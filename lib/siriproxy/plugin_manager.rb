require 'cora'
require 'pp'

class SiriProxy::PluginManager < Cora
  attr_accessor :plugins, :iphone_conn, :guzzoni_conn

  def initialize()
    load_plugins()
  end

  def load_plugins()
    @plugins = []
    if SiriProxy::config.plugins
      SiriProxy::config.plugins.each do |pluginConfig|
          if pluginConfig.is_a? String
            className = pluginConfig
            requireName = "siriproxy-#{className.downcase}"
          else
            className = pluginConfig['name']
            requireName = pluginConfig['require'] || "siriproxy-#{className.downcase}"
          end
          require requireName
          plugin = SiriProxy::Plugin.const_get(className).new(pluginConfig)
          plugin.manager = self
          @plugins << plugin
      end
    end
    log 2, "Plugins loaded: "
    plugins.each{|p| log "-> #{p.class.name}" } if SiriProxy::config.log_level >= 2
  end

  def process_filters(object, direction)
    object_class = object.class #This way, if we change the object class we won't need to modify this code.

    if object['class'] == 'SetRequestOrigin'
      properties = object['properties']
      set_location(properties['latitude'], properties['longitude'], properties)
    end

    plugins.each do |plugin|
      #log "Processing filters on #{plugin} for '#{object["class"]}'"
      new_obj = plugin.process_filters(object, direction)
      object = new_obj if(new_obj == false || new_obj.class == object_class) #prevent accidental poorly formed returns
      return nil if object == false #if any filter returns "false," then the object should be dropped
    end

    return object
  end

  def process(text)
    begin
      result = super(text)
    rescue Exception => e
      log :error, "Exception: #{e.inspect}"
      log 1, e.backtrace
      return nil
    end
    
    self.guzzoni_conn.block_rest_of_session if result

    return result
  end

  def send_request_complete_to_iphone
    log 2, "Sending Request Completed"
    object = generate_request_completed(self.guzzoni_conn.last_ref_id)
    self.guzzoni_conn.inject_object_to_output_stream(object)
    self.guzzoni_conn.block_rest_of_session
  end

  def respond(text, options={})
    self.guzzoni_conn.inject_object_to_output_stream(generate_siri_utterance(self.guzzoni_conn.last_ref_id, text, (options[:spoken] or text), options[:prompt_for_response] == true))
  end

  def no_matches
    return false
  end
end
