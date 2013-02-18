require 'eventmachine'
require 'zlib'
require 'pp'

class String
  def to_hex(seperator=" ")
    bytes.to_a.map{|i| i.to_s(16).rjust(2, '0')}.join(seperator)
  end
end

class SiriProxy

  class << self
    
    def log(level=1, msg)
      SiriProxy::logger.log(level, msg)
    end
    
    def start
      # Setup Loger
      SiriProxy::config.log_file = STDOUT if false == SiriProxy::config.fork
      SiriProxy::logger = SiriProxy::Logger.new(SiriProxy::config.log_file)
      log "Logging to #{(SiriProxy::config.log_file || "/dev/null")}"
      
      if SiriProxy::config.fork
        
        # Ruby 1.8 compatible daemonize
        exit if fork
        Process.setsid
        exit if fork

        write_pid(Process.pid)

        log "Child pid: #{Process.pid}"

        # Reopen Logs
        STDIN.reopen  "/dev/null"
        STDOUT.reopen (SiriProxy::config.log_file || "/dev/null"), "a" 
        STDERR.reopen (SiriProxy::config.log_file || "/dev/null"), "a"
      end

      puts "[====== #{Time.now} Starting Server ======]"

      proxy = self.new      
      proxy.start
    end

    def stop
      puts "Stopping Server"

      pid = get_child_pid
      if pid.nil?
        puts "Server not running."
        Process.exit(1)
      end

      File.unlink("/var/run/#{File.basename(__FILE__)}.pid") rescue nil
      File.unlink("/var/tmp/#{File.basename(__FILE__)}.pid") rescue nil

      puts "Killing server #{pid}"
      Process.kill("HUP", pid)

    end
    
    def restart
      stop
      start
    end
    
    private
    
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
        pidfile1 = "/var/run/#{File.basename(__FILE__)}.pid"
        pidfile2 = "/var/tmp/#{File.basename(__FILE__)}.pid"

        if File.exists?(pidfile1)
          raise "Server Already Running" if process_exists?(File.read(pidfile1).to_i)
          File.unlink(pidfile1)
        elsif File.exists?(pidfile1)
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

        f = File.open("/var/run/#{File.basename(__FILE__)}.pid", "r") rescue nil
        f = File.open("/var/tmp/#{File.basename(__FILE__)}.pid", "r") rescue nil if f.nil?

        pid = f.read().to_i unless f.nil?
        pid
      end
  end

  def initialize()
    EventMachine.run do
      begin
        listen = SiriProxy::config.listen || '127.0.0.1'
        port   = SiriProxy::config.port   || 443

        log "Starting SiriProxy on #{listen}:#{port}.."

        EventMachine::start_server(listen, port, SiriProxy::Connection::Iphone) { |conn|
          log 3, "start conn #{conn.inspect}"
          conn.plugin_manager = SiriProxy::PluginManager.new()
          conn.plugin_manager.iphone_conn = conn
        }

        log "SiriProxy up and running."

      rescue RuntimeError => err
        if err.message == "no acceptor"
          raise "Cannot start the server on port #{SiriProxy::config.port} - are you root, or have another process on this port already?"
        else
          raise
        end
      end
    end  
  end

  def log(level=1, msg)
    @logger.log(level, msg) unless @logger.nil?
  end
  
end