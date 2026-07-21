require "fileutils"
require "pg"

# Long-running process that owns an mpv child and drives the queue. It is the
# sole authority over PlayerState. Commands arrive from Rails/jobs via PostgreSQL
# LISTEN/NOTIFY (see PlayerCommands); playback progress is driven by mpv events.
#
#   * mpv "end-file" (eof/error) -> advance to the next queued track
#   * PG NOTIFY party_player     -> play/pause/stop/skip/volume/seek/queue_changed
#   * 1s ticker                  -> persist position, retry when waiting on cache,
#                                   supervise the mpv process
class PlayerDaemon
  POLL_INTERVAL = 1.0

  def initialize
    @socket_path = PartyConfig[:mpv_ipc_socket]
    @lock = Mutex.new
    @stopping = false   # exit ASAP (force / SIGINT)
    @graceful = false   # exit when the current song ends (SIGTERM)
    @loaded_item_id = nil
  end

  def run
    trap_signals
    launch_mpv
    connect_mpv
    reconcile_on_boot
    Rails.logger.info("[player] ready (socket=#{@socket_path})")
    start_listen_thread
    ticker_loop
  ensure
    shutdown
  end

  private

  # ---- mpv lifecycle ----

  def launch_mpv
    FileUtils.mkdir_p(File.dirname(@socket_path))
    File.unlink(@socket_path) if File.exist?(@socket_path)

    args = ["mpv", "--idle=yes", "--no-video", "--no-terminal",
            "--force-window=no", "--keep-open=no",
            "--input-ipc-server=#{@socket_path}",
            "--volume=#{PlayerState.instance.volume}"]
    if (device = PartyConfig.audio_device)
      args << "--audio-device=#{device}"
    end

    @mpv_pid = Process.spawn(*args)
    Process.detach(@mpv_pid) # auto-reap; we check liveness with kill(0)
    Rails.logger.info("[player] launched mpv pid=#{@mpv_pid}")
  end

  def connect_mpv
    @mpv = MpvClient.new(@socket_path).connect
    @mpv.on_event { |event| handle_event(event) }
    @mpv.set_property("volume", PlayerState.instance.volume)
  end

  # After a restart the queue is intact in the DB, but mpv was killed. Pick the
  # interrupted track back up so a restart doesn't skip a song. If we can't play
  # it (was stopped, or its cache is gone) return it to the queue so it isn't
  # orphaned in the "playing" state.
  def reconcile_on_boot
    state = PlayerState.instance
    item = state.current_queue_item
    return if item.nil? || item.state != "playing"

    if (state.playing? || state.paused?) && item.track.ready_to_play?
      @loaded_item_id = item.id
      @mpv.loadfile(item.track.playable_path)
      @mpv.set_property("pause", !state.playing?)
      state.update!(position_ms: 0)
      Rails.logger.info("[player] resumed '#{item.track.title}' after restart")
    else
      # Return it as "promoted", not "queued": it was the current song, so it keeps
      # its spot at the front. As plain "queued" the next re-deal would throw it
      # back into the round-robin (and a song that was promoted would silently lose
      # its promotion).
      item.update!(state: "promoted")
      state.update!(current_queue_item_id: nil, position_ms: 0, duration_ms: 0)
    end
    PartyBroadcaster.refresh
  rescue => e
    Rails.logger.error("[player] reconcile_on_boot failed: #{e.class}: #{e.message}")
  end

  def mpv_alive?
    return false unless @mpv_pid

    Process.kill(0, @mpv_pid)
    true
  rescue Errno::ESRCH
    false
  end

  def restart_mpv
    Rails.logger.warn("[player] mpv not alive; relaunching")
    @mpv&.close
    @loaded_item_id = nil
    launch_mpv
    connect_mpv
    # Resume: re-arm so the ticker/advance picks the current head back up.
    advance if PlayerState.instance.playing?
  end

  # ---- event + command dispatch ----

  def handle_event(event)
    case event["event"]
    when "end-file"
      # eof = track finished; error = it failed. Both mean "move on".
      # "stop"/"quit"/"redirect" come from our own loadfile/stop — ignore.
      @lock.synchronize { advance(after_playback: true) } if %w[eof error].include?(event["reason"])
    end
  rescue => e
    Rails.logger.error("[player] event error: #{e.class}: #{e.message}")
  end

  def dispatch(payload)
    data = JSON.parse(payload)
    action = data["action"]
    @lock.synchronize do
      case action
      when "play"          then do_play
      when "pause"         then do_pause
      when "stop"          then do_stop
      when "skip"          then advance(after_playback: true)
      when "set_volume"    then do_set_volume(data["volume"])
      when "seek"          then do_seek(data["seconds"])
      when "queue_changed" then do_queue_changed
      else Rails.logger.warn("[player] unknown command #{action.inspect}")
      end
    end
  rescue => e
    Rails.logger.error("[player] command error: #{e.class}: #{e.message}")
  end

  # ---- commands ----

  def do_play
    state = PlayerState.instance
    if @loaded_item_id && state.current_queue_item
      @mpv.set_property("pause", false)
      state.update!(status: "playing")
      PartyBroadcaster.refresh
    else
      advance
    end
  end

  def do_pause
    @mpv.set_property("pause", true)
    PlayerState.instance.update!(status: "paused")
    PartyBroadcaster.refresh
  end

  # Halt and reset to the start, but keep the current track cued. Stop must not
  # drop the song (that would be a skip); adding a track or pressing Play resumes
  # this same song from the beginning.
  def do_stop
    safe_mpv { @mpv.set_property("pause", true) }
    safe_mpv { @mpv.command("seek", 0, "absolute") }
    PlayerState.instance.update!(status: "stopped", position_ms: 0)
    PartyBroadcaster.refresh
  end

  def do_set_volume(value)
    volume = value.to_i.clamp(0, 100)
    @mpv.set_property("volume", volume)
    PlayerState.instance.update!(volume: volume)
    PartyBroadcaster.refresh
  end

  def do_seek(seconds)
    @mpv.command("seek", seconds.to_f, "absolute")
    PlayerState.instance.update!(position_ms: (seconds.to_f * 1000).to_i)
    PartyBroadcaster.refresh
  end

  def do_queue_changed
    state = PlayerState.instance
    cued = @loaded_item_id && state.current_queue_item
    # Adding a track should get music going, unless the user explicitly paused.
    #   * a stopped-but-cued song   -> resume it (Stop keeps the current song)
    #   * idle / drained / stale    -> start the next queued track
    unless state.paused?
      if cued
        do_play if state.stopped?
      elsif QueueItem.head
        @loaded_item_id = nil
        advance
      end
    end
    PrecacheQueueJob.perform_later
  end

  # ---- core queue advance ----

  def advance(after_playback: false)
    state = PlayerState.instance

    # Graceful stop: the current song just finished — mark it played and exit
    # instead of starting the next one.
    if @graceful
      finish_current(state) if after_playback
      @stopping = true
      return
    end

    # Choose the next item while the current one is still "playing", so round-robin
    # fairness counts it (its nick's turn is used up) — otherwise the display and
    # the actual play order would disagree.
    nxt = QueueItem.head
    finish_current(state) if after_playback
    return stop_playback(state) if nxt.nil?

    track = nxt.track
    return wait_for_cache(state, track) unless track.ready_to_play?

    play_item(state, nxt, track)
  end

  def finish_current(state)
    current = state.current_queue_item
    current.update!(state: "played") if current&.state == "playing"
  end

  def stop_playback(state)
    @loaded_item_id = nil
    safe_mpv { @mpv.stop }
    # Stay "armed" (playing) so later additions auto-play, unless explicitly stopped.
    status = state.stopped? ? "stopped" : "playing"
    state.update!(status: status, current_queue_item_id: nil, position_ms: 0, duration_ms: 0)
    PartyBroadcaster.refresh
  end

  def wait_for_cache(state, track)
    ensure_caching(track)
    @loaded_item_id = nil
    state.update!(status: "playing", current_queue_item_id: nil, position_ms: 0, duration_ms: 0)
    PartyBroadcaster.refresh
  end

  def play_item(state, item, track)
    item.update!(state: "playing")
    @loaded_item_id = item.id
    state.update!(status: "playing", current_queue_item_id: item.id,
                  position_ms: 0, duration_ms: track.duration_ms.to_i)
    @mpv.loadfile(track.playable_path)
    @mpv.set_property("pause", false)
    PrecacheQueueJob.perform_later
    PartyBroadcaster.refresh
  end

  def ensure_caching(track)
    return unless track.youtube?
    return if track.cache_status == "pending"

    CacheYoutubeTrackJob.perform_later(track.id)
  end

  # ---- threads / loops ----

  def start_listen_thread
    @command_queue = Queue.new
    start_command_dispatcher

    # The listen thread ONLY reads notifications and hands them off, so heavy
    # command handling never blocks it from draining the socket (mirrors the
    # MpvClient reader/dispatcher split).
    @listen_thread = Thread.new do
      conn = open_listen_connection
      conn.exec("LISTEN #{PlayerCommands::CHANNEL}")
      socket = conn.socket_io
      until @stopping
        conn.consume_input
        while (notification = conn.notifies)
          @command_queue << notification[:extra]
        end
        socket.wait_readable(1)
      end
    rescue => e
      Rails.logger.error("[player] listen thread died: #{e.class}: #{e.message}")
    ensure
      conn&.close
    end
  end

  def start_command_dispatcher
    @command_thread = Thread.new do
      until @stopping
        payload = @command_queue.pop
        dispatch(payload)
      end
    rescue => e
      Rails.logger.error("[player] command dispatcher died: #{e.class}: #{e.message}")
    end
  end

  def open_listen_connection
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    PG.connect(
      host: config[:host], port: config[:port], dbname: config[:database],
      user: config[:username], password: config[:password]
    )
  end

  def ticker_loop
    until @stopping
      tick
      sleep POLL_INTERVAL
    end
  end

  def tick
    # Graceful stop armed and nothing is actively playing (idle, paused, or mpv
    # gone) — there's no song to finish, so exit now.
    if @graceful && !(mpv_alive? && @loaded_item_id && PlayerState.instance.playing?)
      @stopping = true
      return
    end

    restart_mpv unless mpv_alive?

    @lock.synchronize do
      state = PlayerState.instance
      if state.playing? && @loaded_item_id
        persist_position(state)
      elsif state.playing? && @loaded_item_id.nil? && QueueItem.head
        advance # retry after cache completes / new track added
      end
    end
  rescue => e
    Rails.logger.error("[player] tick error: #{e.class}: #{e.message}")
  end

  def persist_position(state)
    pos = safe_mpv { @mpv.get_property("time-pos") }
    return if pos.nil?

    # Persist without callbacks/broadcasts; the UI animates between refreshes.
    state.update_column(:position_ms, (pos.to_f * 1000).to_i)
  end

  def safe_mpv
    yield
  rescue MpvClient::Error => e
    Rails.logger.debug("[player] mpv call failed: #{e.message}")
    nil
  end

  # ---- shutdown ----

  def trap_signals
    # SIGTERM (systemd stop/restart): finish the current song, then exit. A second
    # SIGTERM forces an immediate stop. SIGINT (Ctrl-C) always stops immediately.
    Signal.trap("TERM") { @graceful ? @stopping = true : @graceful = true }
    Signal.trap("INT")  { @stopping = true }
  end

  def shutdown
    return if @shutdown_done

    @shutdown_done = true
    @stopping = true
    @listen_thread&.kill
    @command_thread&.kill
    @mpv&.close
    if mpv_alive?
      Process.kill("TERM", @mpv_pid) rescue nil
    end
    Rails.logger.info("[player] stopped")
  end
end
