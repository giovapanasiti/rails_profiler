module RailsProfiler
  class Configuration
    attr_accessor :enabled, :storage_backend, :redis_url, :sample_rate,
                  :track_queries, :track_code, :retention_days,
                  :dashboard_username, :dashboard_password

    def initialize
      @enabled = Rails.env.production? || Rails.env.staging?
      @storage_backend = :redis
      @redis_url = ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')
      @sample_rate = 0.1 # Sample 10% of requests
      @track_queries = true
      @track_code = true
      @retention_days = 7
      @dashboard_username = ENV.fetch('PROFILER_USERNAME', 'admin')
      @dashboard_password = ENV.fetch('PROFILER_PASSWORD', 'password')
    end
  end
end