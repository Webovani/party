require "socket"
require "json"
require "timeout"

# Thin wrapper over mpv's JSON IPC (--input-ipc-server). Sends commands and
# matches replies by request_id; async events (end-file, property-change) are
# dispatched to a handler registered via #on_event.
class MpvClient
  class Error < StandardError; end

  def initialize(socket_path)
    @socket_path = socket_path.to_s
    @write_mutex = Mutex.new
    @pending_mutex = Mutex.new
    @request_id = 0
    @pending = {}          # request_id => Queue
    @event_handler = nil
    @event_queue = Queue.new
  end

  def on_event(&block)
    @event_handler = block
  end

  # Wait for mpv to create the socket, then connect and start the reader thread.
  def connect(timeout: 15)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    begin
      @socket = UNIXSocket.new(@socket_path)
    rescue Errno::ENOENT, Errno::ECONNREFUSED
      raise Error, "mpv IPC socket #{@socket_path} never appeared" if monotonic > deadline

      sleep 0.1
      retry
    end
    start_reader
    start_dispatcher
    self
  end

  def close
    @reader&.kill
    @dispatcher&.kill
    @socket&.close
  rescue IOError
    # already closed
  end

  # Send a command array, block until mpv replies, return its "data".
  def command(*args, timeout: 10)
    id = next_id
    queue = Queue.new
    @pending_mutex.synchronize { @pending[id] = queue }
    write({ command: args, request_id: id })

    reply = pop_with_timeout(queue, timeout, id)
    error = reply["error"]
    raise Error, "mpv command #{args.inspect} failed: #{error}" if error && error != "success"

    reply["data"]
  end

  def set_property(name, value) = command("set_property", name, value)
  def get_property(name)        = command("get_property", name)
  def observe_property(id, name) = command("observe_property", id, name)
  def loadfile(path)            = command("loadfile", path, "replace")
  def stop                      = command("stop")

  private

  def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def next_id
    @pending_mutex.synchronize { @request_id += 1 }
  end

  def write(hash)
    @write_mutex.synchronize { @socket.write(JSON.generate(hash) + "\n") }
  rescue IOError, Errno::EPIPE => e
    raise Error, "mpv IPC write failed: #{e.message}"
  end

  def pop_with_timeout(queue, timeout, id)
    Timeout.timeout(timeout) { queue.pop }
  rescue Timeout::Error
    @pending_mutex.synchronize { @pending.delete(id) }
    raise Error, "mpv command timed out after #{timeout}s"
  end

  # The reader thread ONLY reads lines and routes them. It never runs user event
  # handlers, so handlers (dispatched on a separate thread) can safely issue
  # blocking commands whose replies this thread reads.
  def start_reader
    @reader = Thread.new do
      Thread.current.abort_on_exception = false
      @socket.each_line { |line| handle_line(line) }
    rescue IOError, Errno::EBADF
      # socket closed; reader exits
    end
  end

  def start_dispatcher
    @dispatcher = Thread.new do
      Thread.current.abort_on_exception = false
      loop do
        event = @event_queue.pop
        @event_handler&.call(event)
      end
    end
  end

  def handle_line(line)
    msg = JSON.parse(line)
    if msg.key?("request_id") && (queue = take_pending(msg["request_id"]))
      queue.push(msg)
    elsif msg["event"]
      @event_queue << msg
    end
  rescue JSON::ParserError
    # ignore malformed line
  end

  def take_pending(id)
    @pending_mutex.synchronize { @pending.delete(id) }
  end
end
