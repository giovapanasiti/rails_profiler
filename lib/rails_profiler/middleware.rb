module RailsProfiler
  class Middleware
    def initialize(app)
      @app = app
      Rails.logger.info "[RailsProfiler] Middleware initialized"
    end

    def call(env)
      Rails.logger.debug "[RailsProfiler] Middleware called for path: #{env['PATH_INFO']}"

      unless should_profile?
        Rails.logger.debug "[RailsProfiler] Skipping profiling (should_profile? returned false)"
        return @app.call(env)
      end

      request_id = SecureRandom.uuid
      request = ActionDispatch::Request.new(env)
      
      Rails.logger.info "[RailsProfiler] Starting profiling for request_id: #{request_id}, path: #{request.path}"

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
      Rails.logger.info "[RailsProfiler] Request completed with status: #{status}, calling profiler.finish"
      profiler.finish(status)

      [status, headers, response]
    ensure
      Thread.current[:rails_profiler_current] = nil
    end

    private

    def should_profile?
      enabled = RailsProfiler.enabled?
      sample = rand < RailsProfiler.config.sample_rate
      sample_rate = RailsProfiler.config.sample_rate
      Rails.logger.debug "[RailsProfiler] should_profile? enabled=#{enabled}, sample_rate=#{sample_rate}, random_hit=#{sample}"
      enabled && sample
    end
  end
end
