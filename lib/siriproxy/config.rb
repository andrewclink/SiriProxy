class SiriProxy
  class << self
    def config
      @@config = SiriProxy::Configuration.new unless defined?(@@config)
      @@config
    end
  end
end

class SiriProxy::Configuration < OpenStruct

  class << self
    ## Configuration Locations
    ## Bundler checks for the existance of this file, so they must be class methods
    ## 
    def config_dir
      if (File.exists?(File.expand_path("~/.siriproxy")) rescue false)
        File.expand_path("~/.siriproxy")
      else
        "/etc/siriproxy.d/"
      end
    end
    
    def config_file
      File.join(self.config_dir, 'config.yml')
    end
  end
  
  # Which file was used?
  # This allows an option to be passed in to determine where to find the config file
  #
  attr_accessor :config_file
    
  def initialize(config_path=nil)
    self.config_file = self.class.config_file if config_path.nil?

    config = {
      :fork              => true, # Only server forks, but it does so by default
      :cmdline_log_level => 0,    # Finds its way to log_level for console
    }.merge(YAML.load_file(self.class.config_file))
    
    super(config)
  end


  def plugins_dir
    File.expand_path(File.join(File.dirname(__FILE__),"..","..","plugins"))
  end
  
  # def to_s
  #   "#<#{self.class}:#{self.id} file=#{config_file}>"
  # end
end
