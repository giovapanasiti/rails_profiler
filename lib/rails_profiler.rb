require "rails_profiler/version"
require "rails_profiler/engine"
require "rails_profiler/configuration"
require "rails_profiler/profiler"
require "rails_profiler/query_tracker"
require "rails_profiler/code_profiler"
require "rails_profiler/storage"
require "rails_profiler/middleware"

module RailsProfiler
  class << self
    attr_accessor :configuration

    def configure
      self.configuration ||= Configuration.new
      yield(configuration)
    end

    def config
      self.configuration ||= Configuration.new
    end

    def profile(name = nil, &block)
      CodeProfiler.profile(name, &block)
    end

    def enabled?
      config.enabled
    end
  end
end