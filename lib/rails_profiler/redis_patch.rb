module RailsProfiler
  module RedisPatch
    def self.apply!
      # Only apply the patch if Redis is defined
      if defined?(Redis)
        puts "[RailsProfiler] Applying Redis compatibility patch"
        
        # First attempt: Try to use Redis with patched initialization
        begin
          # Save the original new method
          Redis.singleton_class.class_eval do
            alias_method :original_new, :new unless method_defined?(:original_new)
            
            # Override Redis.new to filter out problematic parameters
            def new(options = {})
              if options.is_a?(Hash)
                # Remove problematic parameters
                safe_options = options.dup
                safe_options.delete(:allow_retry)
                safe_options.delete(:timeout)
                safe_options.delete(:sentinels)
                safe_options.delete(:reconnect_attempts)
                safe_options.delete(:reconnect_delay)
                safe_options.delete(:reconnect_delay_max)
                
                # Keep only the most basic parameters
                minimal_options = {}
                minimal_options[:url] = safe_options[:url] if safe_options[:url]
                
                # Use original method with filtered options
                puts "[RailsProfiler] Using filtered Redis options: #{minimal_options.inspect}"
                original_new(minimal_options)
              else
                original_new(options)
              end
            rescue => e
              puts "[RailsProfiler] Error creating Redis instance: #{e.message}"
              puts e.backtrace.join("\n") if e.backtrace
              
              # If Redis fails, automatically switch to database storage if available
              if defined?(RailsProfiler.config) && RailsProfiler.config.respond_to?(:disable_redis!)
                RailsProfiler.config.disable_redis!
              end
              
              nil
            end
          end
        rescue => e
          puts "[RailsProfiler] Error while patching Redis: #{e.message}"
          puts e.backtrace.join("\n") if e.backtrace
          
          # If patching fails, try a more aggressive solution: completely disable Redis
          if defined?(RailsProfiler.config) && RailsProfiler.config.respond_to?(:disable_redis!)
            RailsProfiler.config.disable_redis!
          end
        end
      else
        puts "[RailsProfiler] Redis not defined, skipping patch"
      end
    end
  end
end