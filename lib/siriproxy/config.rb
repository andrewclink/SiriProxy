class SiriProxy
  CONFIG_DIR  = File.exists?(File.expand_path("~/.siriproxy")) ? File.expand_path("~/.siriproxy") : "/etc/siriproxy.d/"
  CONFIG_FILE = File.join(CONFIG_DIR, 'config.yml')
  PLUGINS_DIR = File.expand_path(File.join(File.dirname(__FILE__),"..","..","plugins"))
  #PLUGINS_DIR = "/usr/local/siriproxy/plugins"
end
