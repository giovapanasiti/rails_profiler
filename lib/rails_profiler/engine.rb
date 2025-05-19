require "rails"

module RailsProfiler
  class Engine < ::Rails::Engine
    isolate_namespace RailsProfiler

    # Insert middleware earlier in the initialization process
    initializer "rails_profiler.insert_middleware", before: :load_config_initializers do |app|
      puts "Inserting RailsProfiler middleware"
      if RailsProfiler.enabled?
        app.middleware.insert_after ActionDispatch::RequestId, RailsProfiler::Middleware
      end
    end

    initializer "rails_profiler.configure" do |app|
      puts "Configuring RailsProfiler"
      app.config.after_initialize do
        if RailsProfiler.enabled?
          if RailsProfiler.config.track_queries
            RailsProfiler::QueryTracker.install!
          end

          # Set up database cleanup task if using database storage
          if RailsProfiler.config.storage_backend == :database
            setup_database_cleanup
          end
        end
      end
    end

    initializer "rails_profiler.assets" do |app|
      puts "Precompiling assets for RailsProfiler"
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
