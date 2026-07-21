namespace :party do
  desc "Scan the local music library into the tracks table"
  task scan: :environment do
    result = LibraryScanner.new.call
    if result.skipped
      puts "Music directory not present (unmounted?) — nothing scanned."
    else
      puts "Scan complete: #{result.scanned} files, #{result.upserted} added/updated, #{result.pruned} pruned."
    end
  end
end
