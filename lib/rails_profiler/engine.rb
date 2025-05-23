require "rails"

module RailsProfiler
  class Engine < ::Rails::Engine
    isolate_namespace RailsProfiler
    
    # Class variable to store the engine's mount path
    cattr_accessor :mount_path
    self.mount_path = nil

    # Add a very early initializer to catch Redis issues before anything else
    initializer "rails_profiler.check_redis_compatibility", before: :load_config_initializers do |app|
      # Test Redis compatibility
      if defined?(Redis) && RailsProfiler.config.storage_backend == :redis
        begin
          puts "[RailsProfiler] Checking Redis compatibility..."
          # This will trigger our patched Redis.new method
          test_redis = Redis.new(url: RailsProfiler.config.redis_url)
          if test_redis.nil?
            puts "[RailsProfiler] Redis unavailable, switching to database storage if possible"
            RailsProfiler.config.instance_variable_set(:@storage_backend, :database) if defined?(RailsProfiler::Profile)
          end
        rescue => e
          puts "[RailsProfiler] Redis compatibility check failed: #{e.message}"
          # Disable Redis if there's any error
          RailsProfiler.config.instance_variable_set(:@storage_backend, :database) if defined?(RailsProfiler::Profile)
        end
      end
    end

    # Insert middleware earlier in the initialization process
    initializer "rails_profiler.insert_middleware", before: :load_config_initializers do |app|
      puts "[RailsProfiler] Engine initializer: Inserting middleware, enabled=#{RailsProfiler.config.enabled}"
      if RailsProfiler.enabled?
        app.middleware.insert_after ActionDispatch::RequestId, RailsProfiler::Middleware
      end
    end

    initializer "rails_profiler.configure" do |app|
      puts "[RailsProfiler] Engine initializer: Configuring with sample_rate=#{RailsProfiler.config.sample_rate}, redis_url=#{RailsProfiler.config.redis_url}"
      
      app.config.after_initialize do
        if RailsProfiler.enabled?
          puts "[RailsProfiler] Engine after_initialize: Profiling is enabled, using #{RailsProfiler.config.storage_backend} backend"
          
          # Test Redis connectivity if Redis backend is configured
          if RailsProfiler.config.storage_backend == :redis
            begin
              puts "[RailsProfiler] Testing Redis connectivity at #{RailsProfiler.config.redis_url}..."
              # Use standard URI-only initialization to avoid compatibility issues with different Redis versions
              redis = nil
              begin
                redis = Redis.new(url: RailsProfiler.config.redis_url)
                test_key = "rails_profiler:test:#{Time.now.to_i}"
                test_value = "Redis connectivity test at #{Time.now}"
                redis.setex(test_key, 60, test_value)
                retrieved = redis.get(test_key)
                puts "[RailsProfiler] ✅ Redis connection successful. Wrote test key: #{test_key}"
                puts "[RailsProfiler] ✅ Redis test: wrote '#{test_value}', retrieved '#{retrieved}'"
              rescue => e
                puts "[RailsProfiler] ❌ Redis connection ERROR: #{e.class.name} - #{e.message}"
                puts e.backtrace.join("\n")
                puts "[RailsProfiler] Will continue without Redis profiling"
                # Override the storage backend to avoid future errors
                RailsProfiler.config.instance_variable_set(:@storage_backend, :database) if defined?(RailsProfiler::Profile)
              end
            rescue => e
              puts "[RailsProfiler] Unexpected error during Redis setup: #{e.class.name} - #{e.message}"
            end
          end
          
          if RailsProfiler.config.track_queries
            RailsProfiler::QueryTracker.install!
          end

          # Set up database cleanup task if using database storage
          if RailsProfiler.config.storage_backend == :database
            setup_database_cleanup
          end
        else
          puts "[RailsProfiler] Engine after_initialize: Profiling is disabled"
        end
      end
    end

    initializer "rails_profiler.assets" do |app|
      puts "[RailsProfiler] Engine initializer: Precompiling assets"
      app.config.assets.precompile += %w[rails_profiler/application.css rails_profiler/application.js]
    end

    private

    def setup_database_cleanup
      if defined?(ActiveSupport::Reloader)
        ActiveSupport::Reloader.to_prepare do
          # Schedule database cleanup if ActiveJob is available
          if defined?(ActiveJob) && defined?(::Rails.application.config.active_job)
            # Could create a scheduled job here if needed
            # For now we'll rely on the rake task
          end
        end
      end
    end
  end
end
