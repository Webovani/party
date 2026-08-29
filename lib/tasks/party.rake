namespace :party do
  desc "Scan the local music library into the tracks table"
  task scan: :environment do
    require "io/console"

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    # A full scan of a real library is minutes of nothing, so report as we go.
    # On a terminal that is one line rewriting itself, showing the file being
    # read right now; piped to a file or a journal it is a line every 1000 files,
    # which is a readable log rather than a flood. The scanner throttles the
    # callback either way.
    tty  = $stdout.tty?
    root = PartyConfig.music_dir.to_s
    last_logged = 0

    truncate = lambda do |line|
      width = (tty && IO.console&.winsize&.last) || 100
      next line if line.length <= width - 1

      # Cut the middle: the leading counters and the file name are the parts
      # worth keeping, the directories in between are not.
      keep = width - 2
      line[0, keep / 2] + "…" + line[-(keep - keep / 2), keep - keep / 2]
    end

    progress = lambda do |phase, scanned:, total: nil, upserted: 0, path: nil|
      case phase
      when :listing
        $stdout.print("\r\e[K  listing … #{scanned} files") if tty
      when :listed
        tty ? $stdout.print("\r\e[K") : puts("  #{scanned} audio files to consider")
      when :scanning
        rel  = path.to_s.delete_prefix(root).delete_prefix("/")
        line = "  #{scanned}/#{total} · #{upserted} added/updated · #{rel}"
        if tty
          $stdout.print("\r\e[K#{truncate.call(line)}")
        elsif scanned - last_logged >= 1000 || scanned == total
          last_logged = scanned
          puts line
        end
      when :pruning
        $stdout.print("\r\e[K") if tty
        puts "  #{scanned} files, #{upserted} added/updated — pruning removed files …"
      end
      $stdout.flush
    end

    puts "Scanning #{root} …" if root.present?
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
