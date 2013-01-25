class SiriProxy
  class << self
    def config_dir
      begin 
        if File.exists?(File.expand_path("~/.siriproxy"))
          File.expand_path("~/.siriproxy")
        else
          "/etc/siriproxy.d/"
        end
      rescue
        "/etc/siriproxy.d/"
      end
    end
  end
  CONFIG_DIR  = "/etc/siriproxy.d/"
  CONFIG_FILE = File.join(CONFIG_DIR, 'config.yml')
  PLUGINS_DIR = File.expand_path(File.join(File.dirname(__FILE__),"..","..","plugins"))
  #PLUGINS_DIR = "/usr/local/siriproxy/plugins"
end
