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
            def new(*args, **kwargs)
              # Handle different argument patterns to match original method signature
              if args.length == 1 && args.first.is_a?(Hash)
                options = args.first
                # Create minimal options with only essential parameters
                minimal_options = create_minimal_options(options)
                
                # Use original method with filtered options
                puts "[RailsProfiler] Using filtered Redis options: #{minimal_options.inspect}"
                original_new(minimal_options)
              elsif !kwargs.empty?
                # Handle keyword arguments (Ruby 2.7+)
                minimal_kwargs = create_minimal_options(kwargs)
                
                puts "[RailsProfiler] Using filtered Redis kwargs: #{minimal_kwargs.inspect}"
                original_new(**minimal_kwargs)
              else
                # For other patterns (like url string as first arg), pass directly
                puts "[RailsProfiler] Using direct Redis args: #{args.inspect}"
                original_new(*args)
              end
            end
            
            # Helper method to create minimal options
            def create_minimal_options(options)
              # Start with empty hash
              minimal_options = {}
              
              # Only keep essential connection parameters
              minimal_options[:url] = options[:url] if options[:url]
              
              # Add host/port if url not provided
              if !minimal_options[:url] && options[:host]
                minimal_options[:host] = options[:host]
                minimal_options[:port] = options[:port] if options[:port]
                minimal_options[:db] = options[:db] if options[:db]
              end
              
              # Add password if provided (needed for authentication)
              minimal_options[:password] = options[:password] if options[:password]
              
              minimal_options
            rescue => e
                error_type = e.class.name
                puts "[RailsProfiler] Error creating Redis instance: #{error_type} - #{e.message}"
                puts e.backtrace.join("\n") if e.backtrace
                
                # Log more detailed information about the error
                puts "[RailsProfiler] Redis initialization failed with options: #{options.inspect}" if defined?(options) && options
                puts "[RailsProfiler] Redis initialization failed with kwargs: #{kwargs.inspect}" if defined?(kwargs) && !kwargs.empty?
                puts "[RailsProfiler] Redis initialization failed with args: #{args.inspect}" if defined?(args) && !args.empty?
                
                # If Redis fails, automatically switch to database storage if available
                if defined?(RailsProfiler.config) && RailsProfiler.config.respond_to?(:disable_redis!)
                  RailsProfiler.config.disable_redis!
                  puts "[RailsProfiler] Switched to database storage due to Redis error: #{error_type}"
                end
                
                nil
            end
          end
        rescue => e
          error_type = e.class.name
          puts "[RailsProfiler] Error while patching Redis: #{error_type} - #{e.message}"
          puts e.backtrace.join("\n") if e.backtrace
          
          # If patching fails, try a more aggressive solution: completely disable Redis
          if defined?(RailsProfiler.config) && RailsProfiler.config.respond_to?(:disable_redis!)
            RailsProfiler.config.disable_redis!
            puts "[RailsProfiler] Redis has been completely disabled due to patching error: #{error_type}"
            puts "[RailsProfiler] The gem will continue to function using database storage"
          else
            puts "[RailsProfiler] WARNING: Redis patching failed and database fallback is not available"
            puts "[RailsProfiler] Some functionality may be limited"
          end
        end
      else
        puts "[RailsProfiler] Redis not defined, skipping patch"
      end
    end
  end
end