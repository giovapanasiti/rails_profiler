module RailsProfiler
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      return @app.call(env) unless should_profile?

      request_id = SecureRandom.uuid
      profiler = Profiler.new(request_id)
      Thread.current[:rails_profiler_current] = profiler

      status, headers, response = @app.call(env)
      profiler.finish(status)

      [status, headers, response]
    ensure
      Thread.current[:rails_profiler_current] = nil
    end

    private

    def should_profile?
      RailsProfiler.enabled? && rand < RailsProfiler.config.sample_rate
    end
  end
end
