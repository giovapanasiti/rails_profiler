module RailsProfiler
  class CodeProfiler
    class << self
      attr_accessor :stack, :filtered_paths
      
      # Initialize stack if not already set
      def stack
        @stack ||= {}
      end
      
      # Set paths to filter out from profiling (like gems)
      def filtered_paths
        @filtered_paths ||= [
          %r{/gems/},
          %r{/ruby/},
          %r{/bin/},
          %r{/vendor/},
          %r{/lib/rails_profiler/}  # Don't profile the profiler itself
        ]
      end
      
      # Profile a block of code with detailed method tracking
      def profile(name = nil, &block)
        return yield unless RailsProfiler.enabled?

        profiler = Thread.current[:rails_profiler_current]
        return yield unless profiler

        # Determine the call location
        location = caller_locations(1, 1).first
        file_path = location.path
        line_number = location.lineno
        method_name = location.label
        
        # Skip if this is in a filtered path (like gems)
        return yield if should_filter_path?(file_path)
        
        # Generate a name if not provided
        name ||= "#{File.basename(file_path)}:#{line_number}:#{method_name}"
        
        # Track parent method for building call graph
        thread_id = Thread.current.object_id
        parent_method = stack[thread_id]&.last
        
        # Get initial memory usage
        start_memory = get_memory_usage if RailsProfiler.config.track_memory

        # Start timing
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        
        # Add this method to the calling stack
        stack[thread_id] ||= []
        stack[thread_id].push(name)
        
        begin
          result = yield
        ensure
          # End timing
          end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          duration = (end_time - start_time) * 1000
          
          # Calculate memory usage if configured
          memory_delta = nil
          if RailsProfiler.config.track_memory && start_memory
            end_memory = get_memory_usage
            memory_delta = end_memory - start_memory
          end
          
          # Remove from stack
          stack[thread_id].pop
          stack.delete(thread_id) if stack[thread_id]&.empty?
          
          # Determine method type (controller, model, view, etc.)
          method_type = determine_method_type(file_path, method_name, name)
          
          # Record profiling data
          profiler.add_method_profile({
            name: name,
            method_name: method_name,
            method_type: method_type,
            file_path: file_path,
            line_number: line_number,
            duration: duration,
            exclusive_duration: calculate_exclusive_duration(profiler, name, duration),
            memory_delta: memory_delta,
            parent: parent_method,
            started_at: start_time,
            backtrace: caller[0..5]
          })
        end
        
        result
      end
      
      # Profile a specific method in any class
      def profile_method(klass, method_name, options = {})
        return unless RailsProfiler.enabled?
        
        # Skip if already profiled
        method_id = "#{klass.name}##{method_name}"
        return if @profiled_methods&.include?(method_id)
        
        # Track profiled methods to avoid duplicates
        @profiled_methods ||= Set.new
        @profiled_methods << method_id
        
        # Save the original method
        klass.class_eval do
          alias_method :"#{method_name}_without_profiling", method_name
          
          define_method(method_name) do |*args, &block|
            RailsProfiler::CodeProfiler.profile("#{klass.name}##{method_name}") do
              send(:"#{method_name}_without_profiling", *args, &block)
            end
          end
        end
      end
      
      # Automatically profile all controller actions
      def profile_controllers
        return unless RailsProfiler.enabled?
        
        if defined?(ActionController::Base)
          ActionController::Base.class_eval do
            def process_action(*args)
              controller_name = self.class.name
              action_name = self.action_name
              profile_name = "#{controller_name}##{action_name}"
              
              params_data = request.params.except('controller', 'action').to_h
              
              # Track request details
              Thread.current[:rails_profiler_request] = {
                controller: controller_name,
                action: action_name,
                method: request.method,
                path: request.path,
                format: request.format.try(:to_sym),
                params: params_data
              }
              
              RailsProfiler::CodeProfiler.profile(profile_name) do
                super
              end
            end
          end
        end
      end
      
      
      
      # Profile view rendering - improved to handle all argument combinations
      def profile_views
        return unless RailsProfiler.enabled?
        
        if defined?(ActionView::Template)
          ActionView::Template.class_eval do
            alias_method :render_without_profiling, :render
            
            # Update the render method to properly handle all argument types
            def render(*args, &block)
              # Get the full template path - use identifier (absolute path) as the primary source
              full_path = identifier
              
              # Clean up the path to make it more readable
              # Remove the application root path if present to show paths relative to the app
              app_root = Rails.root.to_s if defined?(Rails.root)
              if app_root && full_path.start_with?(app_root)
                relative_path = full_path.sub(app_root, '')
                template_name = "#{relative_path} (#{virtual_path || 'unknown'})"
              else
                # Fallback to using the virtual_path (template path relative to views directory)
                # or full identifier if that's not available
                template_name = virtual_path || full_path
              end
              
              RailsProfiler::CodeProfiler.profile("Render: #{template_name}") do
                # Pass exactly the same arguments to the original method
                render_without_profiling(*args, &block)
              end
            end
          end
        end
      end
      
      # Setup profiling for configured methods from config.auto_profile_methods
      def profile_configured_methods
        return unless RailsProfiler.enabled?
        
        configured_methods = RailsProfiler.config.auto_profile_methods
        return if configured_methods.empty?
        
        configured_methods.each do |method_pattern|
          # Handle patterns like 'User#*' (all methods in User) or 'Post#save' (specific method)
          if method_pattern.include?('#')
            class_name, method_pattern = method_pattern.split('#', 2)
            
            # Find the class
            klass = class_name.constantize rescue nil
            next unless klass
            
            if method_pattern == '*'
              # Profile all instance methods in the class
              klass.instance_methods(false).each do |method_name|
                profile_method(klass, method_name)
              end
            else
              # Profile specific method
              profile_method(klass, method_pattern.to_sym) if klass.method_defined?(method_pattern)
            end
          elsif method_pattern.include?('.')
            # Handle static/class methods like 'User.find_by_email'
            class_name, method_pattern = method_pattern.split('.', 2)
            
            # Find the class
            klass = class_name.constantize rescue nil
            next unless klass
            
            if method_pattern == '*'
              # Profile all class methods
              klass.singleton_class.instance_methods(false).each do |method_name|
                profile_method(klass.singleton_class, method_name)
              end
            else
              # Profile specific class method
              profile_method(klass.singleton_class, method_pattern.to_sym) if klass.singleton_class.method_defined?(method_pattern)
            end
          end
        end
      end
      
      # Calculate exclusive duration (time spent in the method itself, not in called methods)
      def calculate_exclusive_duration(profiler, method_name, duration)
        # This calculation might need to be implemented depending on your profiler's internal structure
        # For now, we'll just return the full duration
        duration
      end
      
      # Determine if a path should be filtered out
      def should_filter_path?(path)
        filtered_paths.any? { |pattern| path =~ pattern }
      end
      
      # Get current memory usage in KB
      def get_memory_usage
        # This works on Linux/macOS, adjust for other platforms as needed
        if RUBY_PLATFORM =~ /darwin/
          `ps -o rss= -p #{Process.pid}`.to_i
        elsif RUBY_PLATFORM =~ /linux/
          File.read("/proc/#{Process.pid}/statm").split(' ')[0].to_i * (Process.page_size / 1024)
        else
          0 # Unsupported platform
        end
      end
      
      # Determine the type of method (controller, model, view, etc.)
      def determine_method_type(file_path, method_name, name)
        if file_path =~ /controllers/
          'controller'
        elsif file_path =~ /models/
          'model'
        elsif file_path =~ /views/ || name.start_with?('Render:')
          'view'
        elsif file_path =~ /jobs/
          'job'
        elsif file_path =~ /services/
          'service'
        elsif file_path =~ /helpers/
          'helper'
        else
          'other'
        end
      end
    end
  end
  
  # Hook to set up automatic profiling
  class Engine < ::Rails::Engine
    initializer "rails_profiler.setup_profiling" do
      if RailsProfiler.config.profile_controllers
        CodeProfiler.profile_controllers 
      end
      
      # Set up automatic profiling of configured methods
      CodeProfiler.profile_configured_methods
      
      # Set up view profiling - now handled by profile_views method to avoid duplicating the patch
      if RailsProfiler.config.track_code && defined?(ActionView::Template)
        CodeProfiler.profile_views
      end
    end
  end
end