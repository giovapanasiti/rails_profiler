namespace :rails_profiler do
  desc "Clean up old profile data from database based on retention period"
  task cleanup: :environment do
    if RailsProfiler.config.storage_backend == :database
      puts "Cleaning up old profile data..."
      deleted_count = RailsProfiler::DatabaseStorage.cleanup_old_profiles
      puts "Cleaned up #{deleted_count} old profiles."
    else
      puts "Cleanup task only applies to database storage backend."
    end
  end
end