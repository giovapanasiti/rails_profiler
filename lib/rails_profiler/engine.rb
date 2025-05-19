require "rails"

module RailsProfiler
  class Engine < ::Rails::Engine
    isolate_namespace RailsProfiler

    initializer "rails_profiler.configure" do |app|
      app.config.after_initialize do
        if RailsProfiler.enabled?
          Rails.application.middleware.insert_after(
            ActionDispatch::RequestId,
            RailsProfiler::Middleware
          )

          if RailsProfiler.config.track_queries
            RailsProfiler::QueryTracker.install!
          end
        end
      end
    end

    initializer "rails_profiler.assets" do |app|
      app.config.assets.precompile += %w[rails_profiler/application.css rails_profiler/application.js]
    end
  end
end
