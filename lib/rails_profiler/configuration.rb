module RailsProfiler
  class Configuration
    attr_accessor :enabled, :storage_backend, :redis_url, :sample_rate,
                  :track_queries, :track_code, :retention_days,
                  :dashboard_username, :dashboard_password,
                  :cleanup_interval, :profile_controllers, :profile_models,
                  :auto_profile_methods, :color_scheme

    # Add a way to completely disable Redis from outside
    def disable_redis!
      @storage_backend = :database
      puts "[RailsProfiler] Redis storage has been disabled due to compatibility issues"
    end

    def initialize
      @enabled = true #Rails.env.production? || Rails.env.staging?
      @storage_backend = :redis
      @redis_url = ENV.fetch('REDIS_URL', 'redis://localhost:6379/12')
      @sample_rate = 0.1 # Sample 10% of requests
      @track_queries = true
      @track_code = true
      @retention_days = 7
      @dashboard_username = ENV.fetch('PROFILER_USERNAME', 'admin')
      @dashboard_password = ENV.fetch('PROFILER_PASSWORD', 'password')
      @cleanup_interval = 1.day # Run cleanup task every day when using database storage
      
      # New options for enhanced method-level profiling
      @profile_controllers = true # Automatically profile all controller actions
      @profile_models = true # Automatically profile model methods 
      @auto_profile_methods = []  # Array of method patterns to auto-profile (e.g. ['User#*', 'Post#save'])
      
      # UI customization
      @color_scheme = {
        primary: "#1E5EFA",       # Skylight blue
        secondary: "#6C47FF",     # Skylight purple
        success: "#2ECC71",       # Green
        warning: "#F1C40F",       # Yellow
        danger: "#E74C3C",        # Red
        info: "#3498DB",          # Blue
        background: "#F5F7FA",    # Light gray background
        card: "#FFFFFF",          # White cards
        text: "#2C3E50",          # Dark text
        muted: "#95A5A6",         # Muted text
        
        # Component-specific colors
        database: "#3498DB",      # Blue for database segments
        view: "#2ECC71",          # Green for view segments
        controller: "#E67E22",    # Orange for controller segments
        ruby: "#9B59B6",          # Purple for Ruby segments
        javascript: "#F1C40F",    # Yellow for JS segments
        api: "#1ABC9C"            # Teal for API segments
      }
    end

    def validate!
      unless [:redis, :database].include?(@storage_backend)
        raise ArgumentError, "Invalid storage_backend: #{@storage_backend}. Valid options are :redis and :database"
      end
    end
  end
end