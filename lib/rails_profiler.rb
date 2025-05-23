require "rails_profiler/version"
require "rails_profiler/configuration"
require "rails_profiler/redis_patch" # Load the Redis patch early
require "rails_profiler/engine"
require "rails_profiler/middleware"
require "rails_profiler/profiler"
require "rails_profiler/query_tracker"
require "rails_profiler/code_profiler"
require "rails_profiler/storage"
require "rails_profiler/debug_patch" # Load the debug patch

# Apply the Redis patch immediately before any Redis operations
RailsProfiler::RedisPatch.apply!

# Add detection of mount path
module ActionDispatch
  module Routing
    class Mapper
      # Store original mount method
      alias_method :original_mount, :mount

      # Override mount method to detect Rails Profiler mounting
      def mount(app, options = nil)
        if app == RailsProfiler::Engine
          path = options[:at] || '/'
          RailsProfiler::Engine.mount_path = path
          puts "[RailsProfiler] Detected engine mount at: #{path}"
        end
        original_mount(app, options)
      end
    end
  end
end

module RailsProfiler
  class << self
    def configure
      @config ||= Configuration.new
      yield(@config)
      @config.validate!
      puts "[RailsProfiler] Configured with storage_backend=#{@config.storage_backend}, enabled=#{@config.enabled}, sample_rate=#{@config.sample_rate}, redis_url=#{@config.redis_url}"
      Rails.logger.info "[RailsProfiler] Configured with storage_backend=#{@config.storage_backend}, enabled=#{@config.enabled}, sample_rate=#{@config.sample_rate}, redis_url=#{@config.redis_url}"
    end

    def config
      @config ||= Configuration.new
    end

    def enabled?
      config.enabled
    end

    def profile(name = nil, &block)
      return yield unless enabled? && config.track_code

      name ||= caller_location_name
      start_time = Time.current

      begin
        yield
      ensure
        duration = (Time.current - start_time) * 1000 # in milliseconds

        if current_profiler
          Rails.logger.debug "[RailsProfiler] Adding code profile: #{name}, duration: #{duration}ms"
          current_profiler.add_profile(name: name, duration: duration)
        else
          Rails.logger.debug "[RailsProfiler] No active profiler for code profile: #{name}"
        end
      end
    end

    def current_profiler
      Thread.current[:rails_profiler_current]
    end

    def engine_mount_path
      RailsProfiler::Engine.mount_path || '/profiler'
    end

    private

    def caller_location_name
      location = caller_locations(2, 1).first
      "#{location.path}:#{location.lineno}"
    end
  end
end