module RailsProfiler
  class CodeProfiler
    def self.profile(name = nil, &block)
      return yield unless RailsProfiler.enabled?

      profiler = Thread.current[:rails_profiler_current]
      return yield unless profiler

      name ||= "#{caller[0].split(':')[0..1].join(':')}"
      start_time = Time.current
      result = yield
      end_time = Time.current

      profiler.add_profile({
        name: name,
        duration: (end_time - start_time) * 1000,
        started_at: start_time,
        backtrace: caller[0..5]
      })

      result
    end
  end
end