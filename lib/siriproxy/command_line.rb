require 'optparse'
require 'siriproxy/configuration'

class SiriProxy::CommandLine
  $LOG_LEVEL = 0
  
  BANNER = <<-EOS
Siri Proxy is a proxy server for Apple's Siri "assistant." The idea is to allow for the creation of custom handlers for different actions. This can allow developers to easily add functionality to Siri.

See: http://github.com/plamoni/SiriProxy/

Usage: siriproxy COMMAND OPTIONS

Commands:
server            Start up the Siri proxy server
genconfig         Generate the default configuration directory
gencerts          Generate a the certificates needed for SiriProxy
bundle            Install any dependancies needed by plugins
console           Launch the plugin test console 
update [dir]      Updates to the latest code from GitHub or from a provided directory
help              Show this usage information

Options:
    Option                           Command       Description
  EOS

  def initialize
    @branch = nil
    parse_options unless ARGV[0] == 'genconfig'
    command     = ARGV.shift
    subcommand  = ARGV.shift
    case command
    when 'server'           then run_server(subcommand)
    when 'gencerts'         then gen_certs
    when 'genconfig'        then gen_config
    when 'bundle'           then run_bundle(subcommand)
    when 'console'          then run_console
    when 'update'           then update(subcommand)
    when 'help'             then usage
    when 'dnsonly'          then dns
    else                    usage
    end
  end

  def run_console
    load_code
    init_plugins

    # this is ugly, but works for now
    SiriProxy::PluginManager.class_eval do
      def respond(text, options={})
        puts "=> #{text}"
      end
      def process(text)
        super(text)
      end
      def send_request_complete_to_iphone
      end
      def no_matches
        puts "No plugin responded"
      end
    end
    SiriProxy::Plugin.class_eval do
      def last_ref_id
        0
      end
      def send_object(object, options={:target => :iphone})
        puts "=> #{object}"
      end
    end

    cora = SiriProxy::PluginManager.new
    repl = -> prompt { print prompt; cora.process(gets.chomp!) }
    loop { repl[">> "] }
  end

  def run_bundle(subcommand='')
    setup_bundler_path
    puts `bundle #{subcommand} #{ARGV.join(' ')}`
  end

  def run_server(subcommand='start')
    puts "--- run_server ---"
    require 'siriproxy'

    case subcommand
    when 'start'
      load_code
      init_plugins
      SiriProxy::start
    when 'stop'     
      SiriProxy::stop
    when 'restart'  
      load_code
      init_plugins
      SiriProxy::restart
    end
  end
  
  def stop_server
    puts "Stopping Server"
    SiriProxy::stop()
  end

  def gen_config
    SiriProxy::Configuration.create_default
  end

  def gen_certs
    ca_name = @ca_name ||= ""
    command = File.join(File.dirname(__FILE__), '..', "..", "scripts", 'gen_certs.sh')
    sp_root = File.join(File.dirname(__FILE__), '..', "..")
    puts `#{command} "#{sp_root}" "#{ca_name}" "#{SiriProxy.config.config_path}"`
  end

  def update(directory=nil)
    if(directory)
      puts "=== Installing from '#{directory}' ==="
      puts `cd #{directory} && rake install`
      puts "=== Bundling ===" if $?.exitstatus == 0
      puts `siriproxy bundle` if $?.exitstatus == 0
      puts "=== SUCCESS ===" if $?.exitstatus == 0
      
      exit $?.exitstatus
    else
      branch_opt = @branch ? "-b #{@branch}" : ""
      @branch = "master" if @branch == nil
      puts "=== Installing latest code from git://github.com/plamoni/SiriProxy.git [#{@branch}] ==="

	  tmp_dir = "/tmp/SiriProxy.install." + (rand 9999).to_s.rjust(4, "0")

	  `mkdir -p #{tmp_dir}`
      puts `git clone #{branch_opt} git://github.com/plamoni/SiriProxy.git #{tmp_dir}`  if $?.exitstatus == 0
      puts "=== Performing Rake Install ===" if $?.exitstatus == 0
      puts `cd #{tmp_dir} && rake install`  if $?.exitstatus == 0
      puts "=== Bundling ===" if $?.exitstatus == 0
      puts `siriproxy bundle`  if $?.exitstatus == 0
      puts "=== Cleaning Up ===" and puts `rm -rf #{tmp_dir}` if $?.exitstatus == 0
      puts "=== SUCCESS ===" if $?.exitstatus == 0

      exit $?.exitstatus
    end 
  end

  def dns
    require 'siriproxy/dns'
    SiriProxy.config.use_dns = true
    server = SiriProxy::Dns.new
    server.run(Logger::DEBUG)
  end

  def usage
    puts "\n#{@option_parser}\n"
  end

  private
  
  def parse_options
    # Google Public DNS servers
    SiriProxy.config.upstream_dns ||= %w[8.8.8.8 8.8.4.4]

    @branch = nil
    @option_parser = OptionParser.new do |opts|
      opts.on('-d', '--dns ADDRESS',     '[server]      Launch DNS server guzzoni.apple.com with ADDRESS (requires root)') do |ip| 
        SiriProxy.config.server_ip = ip
      end
      opts.on('-l', '--log LOG_LEVEL',   '[server]      The level of debug information displayed (higher is more)') do |log_level|
        SiriProxy.config.log_level = log_level
      end
      opts.on('-L', '--listen ADDRESS',  '[server]      Address to listen on (central or node)') do |listen|
        SiriProxy.config.listen = listen
      end
      opts.on('-D', '--upstream-dns SERVERS', Array, '[server]      List of upstream DNS servers to use.  Defaults to \'[8.8.8.8, 8.8.4.4]\'') do |servers|
        SiriProxy.config.upstream_dns = servers
      end
      opts.on('-p', '--port PORT',       '[server]      Port number for server (central or node)') do |port_num|
        SiriProxy.config.port = port_num
      end
      opts.on('-u', '--user USER',       '[server]      The user to run as after launch') do |user|
        SiriProxy.config.user = user
      end
      opts.on('-b', '--branch BRANCH',   '[update]      Choose the branch to update from (default: master)') do |branch|
        @branch = branch
      end
      opts.on('-n', '--name CA_NAME',    '[gencerts]    Define a common name for the CA (default: "SiriProxyCA")') do |ca_name|
        @ca_name = ca_name
      end 
      opts.on('-f', '--foreground',      "[server]   Don't fork into the background") do
        SiriProxy.config.fork = false
      end
      opts.on_tail('-v', '--version',  '              Show version') do
        require "siriproxy/version"
        puts "SiriProxy version #{SiriProxy::VERSION}"
        exit
      end
    end
    @option_parser.banner = BANNER
    @option_parser.parse!(ARGV)
  end

  def setup_bundler_path
    require 'pathname'
    ENV['BUNDLE_GEMFILE'] ||= File.expand_path("../../../Gemfile",
      Pathname.new(__FILE__).realpath)
  end

  def load_code
    setup_bundler_path

    require 'bundler'
    require 'bundler/setup'

    require 'siriproxy'
    require 'siriproxy/connection'
    require 'siriproxy/connection/iphone'
    require 'siriproxy/connection/guzzoni'

    require 'siriproxy/plugin'
    require 'siriproxy/plugin_manager'
  end
  
  def init_plugins
    pManager = SiriProxy::PluginManager.new
    pManager.plugins.each_with_index do |plugin, i|
      if plugin.respond_to?('plugin_init')                                                                     
        SiriProxy.config.plugins[i]['init'] = plugin.plugin_init
      end
    end
    pManager = nil
  end
end
