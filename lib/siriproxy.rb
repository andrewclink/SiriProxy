require 'eventmachine'
require 'zlib'
require 'pp'
require 'siriproxy/configuration'

class String
  def to_hex(seperator=" ")
    bytes.to_a.map{|i| i.to_s(16).rjust(2, '0')}.join(seperator)
  end
end

class SiriProxy

  class << self
    
    def start
      puts "--- start ---"
      proxy = self.new
      puts "Created proxy: #{proxy.inspect}; starting"
      proxy.start()
    end
  
    def stop
      puts "--- stop ---"
      pid = get_child_pid
      if pid.nil?
        puts "Server not running."
        Process.exit(1)
      end

      File.unlink("/var/run/siriproxy.pid") rescue nil
      File.unlink("/var/tmp/siriproxy.pid") rescue nil

      puts "Killing server #{pid}"
      Process.kill("HUP", pid)
    end
    
    def restart
      stop
      start
    end
    
  
    def process_exists?(pid)
      begin
        Process.getpgid( pid )
        true
      rescue Errno::ESRCH
        false
      end
    end
      
    def write_pid(pid)
      f = nil
      pidfile1 = "/var/run/siriproxy.pid"
      pidfile2 = "/var/tmp/siriproxy.pid"

      if File.exists?(pidfile1)
        raise "Server Already Running" if process_exists?(File.read(pidfile1).to_i)
        File.unlink(pidfile1)
      elsif File.exists?(pidfile2)
        raise "Server Already Running" if process_exists?(File.read(pidfile2).to_i)
        File.unlink(pidfile2)
      end

      begin
        f = File.open(pidfile1, "w")
        f.write("#{pid}")
      rescue
        # Didn't have permissions to write to /var/run
        f = File.open(pidfile2, "w")
        f.write("#{pid}")
      ensure
        f.close rescue nil
      end
    end
  
  
    def get_child_pid
      f = nil
      pid = nil

      f = File.open("/var/run/siriproxy.pid", "r") rescue nil
      f = File.open("/var/tmp/siriproxy.pid", "r") rescue nil if f.nil?

      pid = f.read().to_i unless f.nil?
      pid
    end
  end

  def initialize()
    puts "--- SiriProxy#initialize ---"
    # @todo shouldnt need this, make centralize logging instead
    $LOG_LEVEL = SiriProxy.config.log_level.to_i
  end
  
  def do_fork

    # Ruby 1.8 compatible daemonize
    exit if fork
    Process.setsid
    exit if fork

    self.class.write_pid(Process.pid)

    puts "Child pid: #{Process.pid}"

    # Reopen Logs
    STDIN.reopen  "/dev/null"
    STDOUT.reopen (SiriProxy::config.log_file || "/dev/null"), "a" 
    STDERR.reopen (SiriProxy::config.log_file || "/dev/null"), "a"

  end
  
  def start
    ## Go into the background if appropriate
    do_fork if SiriProxy.config.fork

    ## Start DNS Server if appropriate
    if SiriProxy.config.server_ip
      puts "Starting DNS Server"
      require 'siriproxy/dns'
      dns_server = SiriProxy::Dns.new
      dns_server.start()
    end

    ## Everything's bootstrapped; start the EM reactor
    start_server
    
  end

  def start_server
    EventMachine.run do
      if Process.uid == 0 && !SiriProxy.config.user
        puts "[Notice - Server] ======================= WARNING: Running as root ============================="
        puts "[Notice - Server] You should use -l or the config.yml to specify and non-root user to run under"
        puts "[Notice - Server] Running the server as root is dangerous."
        puts "[Notice - Server] =============================================================================="
      end

      begin
        listen_addr = SiriProxy.config.listen || "0.0.0.0"
        puts "[Info - Server] Starting SiriProxy on #{listen_addr}:#{SiriProxy.config.port}..."
        EventMachine::start_server(listen_addr, SiriProxy.config.port, SiriProxy::Connection::Iphone, SiriProxy.config.upstream_dns) { |conn|
          puts "[Info - Guzzoni] Starting conneciton #{conn.inspect}" if $LOG_LEVEL < 1
          conn.plugin_manager = SiriProxy::PluginManager.new()
          conn.plugin_manager.iphone_conn = conn
        }
      
        retries = 0
        while SiriProxy.config.server_ip && !$SP_DNS_STARTED && retries <= 5
          puts "[Info - Server] DNS server is not running yet, waiting #{2**retries} second#{'s' if retries > 1}..."
          sleep 2**retries
          retries += 1
        end

        if retries > 5
          puts "[Error - Server] DNS server did not start up."
          exit 1
        end

        EventMachine.set_effective_user(SiriProxy.config.user) if SiriProxy.config.user
        puts "[Info - Server] SiriProxy up and running."

      rescue RuntimeError => err
        if err.message == "no acceptor"
          raise "[Error - Server] Cannot start the server on port #{SiriProxy.config.port} - are you root, or have another process on this port already?"
        else
          raise
        end
      end
    end
  end


  
end
