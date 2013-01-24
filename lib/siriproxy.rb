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
    def start

      childpid = fork do
        write_pid(Process.pid)

        proxy = self.new
        proxy.start

        STDIN.reopen "/dev/null"
        STDOUT.reopen "/dev/null", "a" 
        STDERR.reopen "/dev/null", "a"
        Process.daemon
        

      end#fork

      Process.detach(childpid)
      Process.exit(0)

    end

    def stop
      puts "Stopping Echo Server"

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
    
    private

      def write_pid(pid)
        f = nil
        pidfile1 = "/var/run/#{File.basename(__FILE__)}.pid"
        pidfile2 = "/var/tmp/#{File.basename(__FILE__)}.pid"

        raise "Server Already Running" if File.exists?(pidfile1)
        raise "Server Already Running" if File.exists?(pidfile2)

        begin
          f = File.open(pidfile1, "w")
          f.write("#{pid}")
        rescue
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
    # @todo shouldnt need this, make centralize logging instead
    $LOG_LEVEL = $APP_CONFIG.log_level.to_i
    EventMachine.run do
      begin
        listen = $APP_CONFIG.listen || '127.0.0.1'
        port   = $APP_CONFIG.port   || 443

        puts "Starting SiriProxy on #{listen}:#{port}.."

        EventMachine::start_server(listen, port, SiriProxy::Connection::Iphone) { |conn|
          $stderr.puts "start conn #{conn.inspect}"
          conn.plugin_manager = SiriProxy::PluginManager.new()
          conn.plugin_manager.iphone_conn = conn
        }

        puts "SiriProxy up and running."

      rescue RuntimeError => err
        if err.message == "no acceptor"
          raise "Cannot start the server on port #{$APP_CONFIG.port} - are you root, or have another process on this port already?"
        else
          raise
        end
      end
    end  
  end

end
