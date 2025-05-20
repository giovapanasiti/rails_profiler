module RailsProfiler
  class Profiler
    # Override finish method to ensure hotspots are properly generated
    alias_method :original_finish, :finish
    
    def finish(status = nil, duration = nil)
      # Handle case when no arguments are provided
      if status.nil?
        Rails.logger.debug "[RailsProfiler] Finishing profile #{@request_id} with no status provided"
        status = 200 # Default to success status
      end
      
      total_duration = duration || calculate_duration
      
      # Debug what's happening
      Rails.logger.debug "[RailsProfiler] Finishing profile #{@request_id} with #{@code_profiles.size} code profiles"
      
      # Make sure we generate hotspots even with limited data
      ensure_hotspots
      
      # Continue with original implementation using explicit arguments
      original_finish(status, duration)
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
        duration = calculate_duration rescue 0
        @hotspots[:controllers][controller_name][:total_time] = @controller_time > 0 ? @controller_time : duration
        
        # Add action info
        if action_name
          @hotspots[:controllers][controller_name][:actions][action_name] = {
            count: 1,
            total_time: @controller_time > 0 ? @controller_time : duration
          }
        end
        
        Rails.logger.debug "[RailsProfiler] Created controller hotspot for #{controller_name}"
      end
      
      # If we have code profiles but no method hotspots, create some
      if @code_profiles.any? && @hotspots[:methods].empty?
        @code_profiles.each do |profile|
          # Handle different profile formats safely
          begin
            # Skip if profile is not a hash or doesn't have required data
            next unless profile.is_a?(Hash)
            
            method_name = profile[:name]
            next unless method_name
            
            # Skip if it's a controller method we've already tracked
            next if method_name.include?('Controller') && method_name.include?('#')
            
            # Get duration values safely
            duration = profile[:duration] || 0
            exclusive_duration = profile[:exclusive_duration] || duration || 0
            
            # Create method hotspot
            @hotspots[:methods][method_name] ||= { 
              count: 1,
              total_time: duration,
              exclusive_time: exclusive_duration
            }
            
            Rails.logger.debug "[RailsProfiler] Created method hotspot for #{method_name}"
          rescue => e
            Rails.logger.error "[RailsProfiler] Error processing code profile: #{e.message}"
          end
        end
      end
    end
  end
end