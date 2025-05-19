module RailsProfiler
  class Middleware
    def initialize(app)
      @app = app
      puts "[RailsProfiler] Middleware initialized with config: enabled=#{RailsProfiler.config.enabled}, storage=#{RailsProfiler.config.storage_backend}, sample_rate=#{RailsProfiler.config.sample_rate}"
      Rails.logger.info "[RailsProfiler] Middleware initialized with config: enabled=#{RailsProfiler.config.enabled}, storage=#{RailsProfiler.config.storage_backend}, sample_rate=#{RailsProfiler.config.sample_rate}"
    end

    def call(env)
      puts "[RailsProfiler] ⚡ Middleware called for path: #{env['PATH_INFO']}"

      unless should_profile?
        puts "[RailsProfiler] ❌ Skipping profiling (should_profile? returned false)"
        return @app.call(env)
      end

      request_id = SecureRandom.uuid
      request = ActionDispatch::Request.new(env)
      
      puts "[RailsProfiler] ✅ Starting profiling for request_id: #{request_id}, path: #{request.path}"

      # Create profiler with request information
      profiler = Profiler.new(
        request_id,
        url: request.url,
        method: request.method,
        path: request.path,
        format: request.format.to_s
      )
      
      Thread.current[:rails_profiler_current] = profiler

      status, headers, response = @app.call(env)
      puts "[RailsProfiler] ✅ Request completed with status: #{status}, calling profiler.finish"
      profiler.finish(status)

      [status, headers, response]
    ensure
      Thread.current[:rails_profiler_current] = nil
    end

    private

    def should_profile?
      enabled = RailsProfiler.config.enabled
      sample_rate = RailsProfiler.config.sample_rate
      sample = rand < sample_rate
      puts "[RailsProfiler] should_profile? enabled=#{enabled}, sample_rate=#{sample_rate}, random_hit=#{sample}"
      enabled && sample
    end
  end
end
