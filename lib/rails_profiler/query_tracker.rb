require "active_record"

module RailsProfiler
  class QueryTracker
    def self.install!
      Rails.logger.info "[RailsProfiler] Installing QueryTracker"
      
      ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        profiler = Thread.current[:rails_profiler_current]
        
        if profiler && !ignored_query?(event.payload[:sql])
          Rails.logger.debug "[RailsProfiler] QueryTracker captured SQL query: #{event.payload[:sql].truncate(100)}" if rand < 0.1
          
          query_data = {
            sql: event.payload[:sql],
            name: event.payload[:name],
            duration: event.duration,
            started_at: event.time
          }
          
          if event.payload[:binds].present? && event.payload[:type_casted_binds].respond_to?(:call)
            binds = event.payload[:type_casted_binds].call(event.payload[:binds])
            query_data[:binds] = binds.map(&:to_s) if binds.present?
          end
          
          if collect_backtrace?
            query_data[:backtrace] = clean_backtrace(caller)
          end
          
          profiler.add_query(query_data)
        end
      end
      
      Rails.logger.info "[RailsProfiler] QueryTracker successfully installed"
    end
    
    private
    
    def self.ignored_query?(sql)
      sql =~ /\A(BEGIN|COMMIT|ROLLBACK|RELEASE|SAVEPOINT)/i
    end
    
    def self.collect_backtrace?
      true # Could make this configurable
    end
    
    def self.clean_backtrace(backtrace)
      app_root = Rails.root.to_s
      
      backtrace
        .select { |line| line.include?(app_root) }
        .map { |line| line.sub(app_root, '') }
        .first(10)
    end
  end
end