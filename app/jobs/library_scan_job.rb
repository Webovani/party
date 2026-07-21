class LibraryScanJob < ApplicationJob
  queue_as :default

  # Only one meaningful scan at a time.
  def perform
    result = LibraryScanner.new.call
    Rails.logger.info("[LibraryScanJob] #{result.to_h}")
    result
  end
end
