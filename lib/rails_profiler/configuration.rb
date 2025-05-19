module RailsProfiler
  class Configuration
    attr_accessor :enabled, :storage_backend, :redis_url, :sample_rate,
                  :track_queries, :track_code, :retention_days,
                  :dashboard_username, :dashboard_password,
                  :cleanup_interval

    def initialize
      @enabled = true #Rails.env.production? || Rails.env.staging?
      @storage_backend = :redis
      @redis_url = ENV.fetch('REDIS_URL', 'redis://localhost:6379/12')
      @sample_rate = 0.1 # Sample 10% of requests
      @track_queries = true
      @track_code = true
      @retention_days = 7
      @dashboard_username = ENV.fetch('PROFILER_USERNAME', 'admin')
      @dashboard_password = ENV.fetch('PROFILER_PASSWORD', 'password')
      @cleanup_interval = 1.day # Run cleanup task every day when using database storage
    end

    def validate!
      unless [:redis, :database].include?(@storage_backend)
        raise ArgumentError, "Invalid storage_backend: #{@storage_backend}. Valid options are :redis and :database"
      end
    end
  end
end