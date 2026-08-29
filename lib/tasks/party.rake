namespace :party do
  desc "Scan the local music library into the tracks table"
  task scan: :environment do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    # A full scan of a real library is minutes of nothing, so report as we go.
    # On a terminal that is one line rewriting itself; piped to a file or a
    # journal it is a line every 1000 files, which is a readable log rather than
    # a flood. The scanner throttles the callback either way.
    tty = $stdout.tty?
    last_logged = 0

    progress = lambda do |phase, scanned:, upserted:|
      case phase
      when :start
        puts "Scanning #{PartyConfig.music_dir} …"
      when :scanning
        line = "  #{scanned} files, #{upserted} added/updated"
        if tty
          $stdout.print("\r\e[K#{line}")
        elsif scanned - last_logged >= 1000
          last_logged = scanned
          puts line
        end
      when :pruning
        $stdout.print("\r\e[K") if tty
        puts "  #{scanned} files, #{upserted} added/updated — pruning removed files …"
      end
      $stdout.flush
    end

    result = LibraryScanner.new(progress: progress).call
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    if result.reason == :disabled
      puts "No music_dir configured — this box runs YouTube-only; nothing scanned."
    elsif result.skipped
      puts "Music directory not present (unmounted?) — nothing scanned."
    else
      puts format("Scan complete in %.1fs: %d files, %d added/updated, %d pruned.",
                  elapsed, result.scanned, result.upserted, result.pruned)
    end
  end
end
