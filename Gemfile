source "https://rubygems.org"

gemspec

# load plugins
require 'yaml'
require 'ostruct'
load 'siriproxy/config.rb'

if !File.exists?(SiriProxy::Configuration.config_file)
  $stderr.puts "config.yml not found in #{SiriProxy::Config.config_dir}"
  $stderr.puts "Copy config.example.yml to config.yml, then modify it."
  exit 1
end

gem 'cora', :git => "git://github.com/andrewclink/cora-0.0.4.git"

config = SiriProxy::config
if config.plugins
  config.plugins.each do |plugin|
    if plugin.is_a? String
      gem "siriproxy-#{plugin.downcase}"
    else
      gem "siriproxy-#{plugin['gem'] || plugin['name'].downcase}", :path => plugin['path'], :git => plugin['git'], :branch => plugin['branch'], :require => plugin['require']
    end
  end
end
