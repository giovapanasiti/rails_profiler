module RailsProfiler
  class Middleware
    def initialize(app)
      @app = app
      Rails.logger.info "[RailsProfiler] Middleware initialized with config: enabled=#{RailsProfiler.config.enabled}, storage=#{RailsProfiler.config.storage_backend}, sample_rate=#{RailsProfiler.config.sample_rate}"
    end

    def call(env)
      # Create a request object early to check if it's a profiler request
      request = ActionDispatch::Request.new(env)

      unless should_profile?(request)
        return @app.call(env)
      end

      request_id = SecureRandom.uuid
      
      Rails.logger.debug "[RailsProfiler] ✅ Starting profiling for request_id: #{request_id}, path: #{request.path}"

      # Start timing the entire request
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      
      # Create profiler with request information
      profiler = Profiler.new(
        request_id,
        url: request.url,
        method: request.method,
        path: request.path,
        format: request.format.to_s
      )
      
      Thread.current[:rails_profiler_current] = profiler

      # Execute the request
      status, headers, response = @app.call(env)
      
      # Calculate total duration
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      duration = (end_time - start_time) * 1000 # ms
      
      # Extract controller/action from env
      controller = env['action_controller.instance']
      if controller
        profiler.add_controller_info(
          controller: controller.class.name,
          action: env['action_dispatch.request.path_parameters'][:action]
        )
      end
      
      # Add segments data based on instrumentation results
      profiler.process_segments(duration)
      
      if status < 100 
        Rails.logger.error "[RailsProfiler] ❌ Invalid status code: #{status} for request_id: #{request_id}"
        return [status, headers, response]
      end

      # Finish profiling and store the data
      profiler.finish(status, duration)

      [status, headers, response]
    ensure
      Thread.current[:rails_profiler_current] = nil
    end

    private

    def should_profile?(request)
      enabled = RailsProfiler.config.enabled
      sample_rate = RailsProfiler.config.sample_rate
      sample = rand < sample_rate
      
      # Get the mount path from the engine
      mount_path = RailsProfiler.engine_mount_path
      
      # Check if this is a request to the profiler engine itself
      # Handle both exact matches and sub-paths
      is_profiler_request = request.path == mount_path || 
                            (mount_path != '/' && request.path.start_with?(mount_path))
      
      if is_profiler_request
        return false
      end
      
      # Skip asset requests
      is_asset_request = request.path.start_with?('/assets/', '/packs/', '/images/', '/javascripts/', '/stylesheets/')
      
      enabled && sample && !is_profiler_request && !is_asset_request
    end
  end
end
