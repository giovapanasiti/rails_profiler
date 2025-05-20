module RailsProfiler
  class Profiler
    # Override finish method to ensure hotspots are properly generated
    alias_method :original_finish, :finish
    
    def finish(*args)
      # Get the original data that would be stored
      status = args.first
      duration = args.length > 1 ? args[1] : nil
      
      total_duration = duration || calculate_duration
      
      # Debug what's happening
      Rails.logger.debug "[RailsProfiler] Finishing profile #{@request_id} with #{@code_profiles.size} code profiles"
      
      # Make sure we generate hotspots even with limited data
      ensure_hotspots
      
      # Continue with original implementation using the same arguments as received
      original_finish(*args)
    end
    
    private
    
    # Ensure hotspots are generated even with limited data
    def ensure_hotspots
      # Debug controller info
      Rails.logger.debug "[RailsProfiler] Controller: #{@controller}, Action: #{@action}"
      
      # If we have controller info but no controller hotspots, create one
      if @controller && @hotspots[:controllers].empty?
        controller_name = @controller
        action_name = @action
        
        # Create controller hotspot
        @hotspots[:controllers][controller_name] ||= { 
          actions: {}, 
          total_time: 0 
        }
        
        # Use total duration if we don't have specific controller time
        @hotspots[:controllers][controller_name][:total_time] = @controller_time > 0 ? @controller_time : calculate_duration
        
        # Add action info
        if action_name
          @hotspots[:controllers][controller_name][:actions][action_name] = {
            count: 1,
            total_time: @controller_time > 0 ? @controller_time : calculate_duration
          }
        end
        
        Rails.logger.debug "[RailsProfiler] Created controller hotspot for #{controller_name}"
      end
      
      # If we have code profiles but no method hotspots, create some
      if @code_profiles.any? && @hotspots[:methods].empty?
        @code_profiles.each do |profile|
          method_name = profile.is_a?(Hash) ? profile[:name] : nil
          next unless method_name
          
          # Skip if it's a controller method we've already tracked
          next if method_name.include?('Controller') && method_name.include?('#')
          
          # Create method hotspot
          @hotspots[:methods][method_name] ||= { 
            count: 1,
            total_time: profile[:duration] || 0,
            exclusive_time: profile[:exclusive_duration] || profile[:duration] || 0
          }
          
          Rails.logger.debug "[RailsProfiler] Created method hotspot for #{method_name}"
        end
      end
    end
  end
end