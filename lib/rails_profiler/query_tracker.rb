require "active_record"

module RailsProfiler
  class QueryTracker
    def self.install!
      ActiveRecord::Base.connection.class.class_eval do
        alias_method :execute_without_profiler, :execute

        def execute(sql, name = nil)
          if RailsProfiler.enabled? && current_profiler
            start_time = Time.current
            result = execute_without_profiler(sql, name)
            end_time = Time.current

            current_profiler.add_query({
              sql: sql,
              name: name,
              duration: (end_time - start_time) * 1000,
              started_at: start_time,
              backtrace: caller[0..10]
            })

            result
          else
            execute_without_profiler(sql, name)
          end
        end

        private

        def current_profiler
          Thread.current[:rails_profiler_current]
        end
      end
    end
  end
end