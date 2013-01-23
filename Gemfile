source :gemcutter

gemspec

# load plugins
require 'yaml'
require 'ostruct'
load 'siriproxy/config.rb'

if !File.exists?(SiriProxy::CONFIG_FILE)
  $stderr.puts "config.yml not found. Copy config.example.yml to config.yml, then modify it."
  exit 1
end

gem 'cora', '0.0.4'

config = OpenStruct.new(YAML.load_file(SiriProxy::CONFIG_FILE))
if config.plugins
  config.plugins.each do |plugin|
    if plugin.is_a? String
      gem "siriproxy-#{plugin.downcase}"
    else
      gem "siriproxy-#{plugin['gem'] || plugin['name'].downcase}", :path => plugin['path'], :git => plugin['git'], :branch => plugin['branch'], :require => plugin['require']
    end
  end
end
