module RailsProfiler
  class DashboardController < ApplicationController
    helper_method :generate_sample_time_data
    
    def index
      @stats = Storage.get_summary_stats
      @profiles = @stats[:latest_profiles] || []
      @endpoints = @stats[:endpoints] || []
      
      # Prepare time-series data for charts
      prepare_time_series_data
      
      # Prepare performance breakdown data
      prepare_performance_data
      
      # Prepare query distribution data
      prepare_query_distribution
    end

    def show
      @profile = Storage.get_profile(params[:id])
      redirect_to rails_profiler.root_path unless @profile
    end

    def profiles
      page = (params[:page] || 1).to_i
      per_page = 50
      offset = (page - 1) * per_page
      
      @profiles = Storage.get_profiles(limit: per_page, offset: offset)
      @current_page = page
    end
    
    def endpoints
      @stats = Storage.get_summary_stats
      @endpoints = @stats[:endpoints] || []
      
      # Allow filtering by specific endpoint
      if params[:endpoint]
        @selected_endpoint = params[:endpoint]
        @endpoint_profiles = Storage.get_profiles_by_endpoint(@selected_endpoint, limit: 100)
      end
    end
    
    def trends
      days = (params[:days] || 7).to_i
      @trends_data = Storage.get_trends(days: days)
    end
    
    def slowest_queries
      limit = (params[:limit] || 50).to_i
      @profiles = Storage.get_profiles(limit: 200) # Get more profiles to find slow queries
      
      # Extract all queries from profiles
      all_queries = []
      @profiles.each do |profile|
        profile[:queries].each do |query|
          all_queries << {
            sql: query[:sql],
            duration: query[:duration],
            name: query[:name],
            request_id: profile[:request_id],
            path: profile[:path],
            started_at: profile[:started_at],
            endpoint_name: profile[:endpoint_name]
          }
        end
      end
      
      # Sort queries by duration (slowest first) and limit
      @slowest_queries = all_queries.sort_by { |q| -q[:duration] }.first(limit)
    end
    
    def hotspots
      # Get recent profiles to analyze hotspots
      @profiles = Storage.get_profiles(limit: 500)
      
      # Initialize hotspot data structure
      hotspots = {
        controllers: {},
        methods: {},
        models: {},
        views: {}
      }
      
      # Debug log the number of profiles we're examining
      Rails.logger.debug "[RailsProfiler] Analyzing #{@profiles.size} profiles for hotspots"
      
      # Aggregate hotspot data from all profiles
      @profiles.each do |profile|
        # Handle basic controller data even without hotspots
        if profile[:controller].present?
          controller_name = profile[:controller] 
          action_name = profile[:action]
          
          # Create basic controller hotspot entry if there's no detailed data
          hotspots[:controllers][controller_name] ||= { total_time: 0, count: 0, actions: {} }
          hotspots[:controllers][controller_name][:total_time] += profile[:duration] || 0
          hotspots[:controllers][controller_name][:count] += 1
          
          if action_name.present?
            hotspots[:controllers][controller_name][:actions][action_name] ||= { total_time: 0, count: 0 }
            hotspots[:controllers][controller_name][:actions][action_name][:total_time] += profile[:duration] || 0
            hotspots[:controllers][controller_name][:actions][action_name][:count] += 1
          end
        end
        
        # Process detailed hotspot data if available
        if profile[:additional_data].is_a?(Hash)
          # Try to process hotspots data
          if profile[:additional_data][:hotspots].is_a?(Hash)
            profile_hotspots = profile[:additional_data][:hotspots]
            
            # Aggregate controller hotspots
            if profile_hotspots[:controllers].is_a?(Array) && !profile_hotspots[:controllers].empty?
              profile_hotspots[:controllers].each do |controller|
                next unless controller.is_a?(Hash) && controller[:name].present?
                
                name = controller[:name]
                hotspots[:controllers][name] ||= { total_time: 0, count: 0, actions: {} }
                hotspots[:controllers][name][:total_time] += controller[:value] || 0
                hotspots[:controllers][name][:count] += 1
                
                if controller[:data].is_a?(Hash) && controller[:data][:actions].is_a?(Hash)
                  controller[:data][:actions].each do |action, action_data|
                    next unless action_data.is_a?(Hash)
                    
                    hotspots[:controllers][name][:actions][action] ||= { total_time: 0, count: 0 }
                    hotspots[:controllers][name][:actions][action][:total_time] += action_data[:total_time] || 0
                    hotspots[:controllers][name][:actions][action][:count] += action_data[:count] || 1
                  end
                end
              end
            end
            
            # Aggregate method hotspots
            if profile_hotspots[:methods].is_a?(Array) && !profile_hotspots[:methods].empty?
              profile_hotspots[:methods].each do |method|
                next unless method.is_a?(Hash) && method[:name].present?
                
                name = method[:name]
                hotspots[:methods][name] ||= { exclusive_time: 0, total_time: 0, count: 0 }
                hotspots[:methods][name][:exclusive_time] += method[:value] || 0
                
                if method[:data].is_a?(Hash)
                  hotspots[:methods][name][:total_time] += method[:data][:total_time] || method[:value] || 0
                  hotspots[:methods][name][:count] += method[:data][:count] || 1
                else
                  hotspots[:methods][name][:total_time] += method[:value] || 0
                  hotspots[:methods][name][:count] += 1
                end
              end
            end
            
            # Aggregate model hotspots
            if profile_hotspots[:models].is_a?(Array) && !profile_hotspots[:models].empty?
              profile_hotspots[:models].each do |model|
                next unless model.is_a?(Hash) && model[:name].present?
                
                name = model[:name]
                hotspots[:models][name] ||= { total_time: 0, count: 0 }
                hotspots[:models][name][:total_time] += model[:value] || 0
                hotspots[:models][name][:count] += (model[:data].is_a?(Hash) ? model[:data][:count] || 1 : 1)
              end
            end
            
            # Aggregate view hotspots
            if profile_hotspots[:views].is_a?(Array) && !profile_hotspots[:views].empty?
              profile_hotspots[:views].each do |view|
                next unless view.is_a?(Hash) && view[:name].present?
                
                name = view[:name]
                hotspots[:views][name] ||= { total_time: 0, count: 0 }
                hotspots[:views][name][:total_time] += view[:value] || 0
                hotspots[:views][name][:count] += (view[:data].is_a?(Hash) ? view[:data][:count] || 1 : 1)
              end
            end
          end
          
          # Try to extract method data from profiles if method hotspots are empty
          if hotspots[:methods].empty? && profile[:additional_data][:profiles].is_a?(Hash)
            profile[:additional_data][:profiles].each do |method_name, data|
              next if method_name.include?('Controller') # Skip controller methods to avoid duplication
              next unless data.is_a?(Hash)
              
              hotspots[:methods][method_name] ||= { 
                exclusive_time: 0, 
                total_time: 0, 
                count: 0 
              }
              
              hotspots[:methods][method_name][:exclusive_time] += data[:exclusive_duration] || 0
              hotspots[:methods][method_name][:total_time] += data[:total_duration] || 0
              hotspots[:methods][method_name][:count] += data[:count] || 1
            end
          end
        end
      end
      
      # Format the data for the view
      @hotspots = {
        controllers: format_hotspot_data(hotspots[:controllers], :total_time, 10),
        methods: format_hotspot_data(hotspots[:methods], :exclusive_time, 20),
        models: format_hotspot_data(hotspots[:models], :total_time, 10),
        views: format_hotspot_data(hotspots[:views], :total_time, 10)
      }
      
      # Log what we found
      Rails.logger.debug "[RailsProfiler] Found #{@hotspots[:controllers].size} controller hotspots"
      Rails.logger.debug "[RailsProfiler] Found #{@hotspots[:methods].size} method hotspots"
      
      # Get maximum times for scaling progress bars (with fallbacks)
      @max_controller_time = (@hotspots[:controllers].first&.dig(:value) || 100) rescue 100
      @max_method_time = (@hotspots[:methods].first&.dig(:value) || 100) rescue 100
    end
    
    def flame_graph
      # Get data for the flame graph visualization
      @profile_id = params[:profile_id]
      
      if @profile_id
        @profile = Storage.get_profile(@profile_id)
        @flame_data = prepare_flame_graph_data(@profile) if @profile
      else
        # Without a specific profile, use the most recent profile with code profiling data
        profiles = Storage.get_profiles(limit: 10)
        @profile = profiles.find { |p| p[:additional_data] && p[:additional_data][:profiles].present? }
        @flame_data = prepare_flame_graph_data(@profile) if @profile
      end
      
      # Get a list of recent profiles with code profiling data for the dropdown
      @available_profiles = Storage.get_profiles(limit: 50).select do |p| 
        p[:additional_data] && p[:additional_data][:profiles].present?
      end
    end
    
    def call_graph
      # Get data for the call graph visualization
      @profile_id = params[:profile_id]
      
      if @profile_id
        @profile = Storage.get_profile(@profile_id)
        @call_graph_data = prepare_call_graph_data(@profile) if @profile
      else
        # Without a specific profile, use the most recent profile with code profiling data
        profiles = Storage.get_profiles(limit: 10)
        @profile = profiles.find { |p| p[:additional_data] && p[:additional_data][:call_graph].present? }
        @call_graph_data = prepare_call_graph_data(@profile) if @profile
      end
      
      # Get a list of recent profiles with code profiling data for the dropdown
      @available_profiles = Storage.get_profiles(limit: 50).select do |p| 
        p[:additional_data] && p[:additional_data][:call_graph].present?
      end
    end
    
    private
    
    def prepare_time_series_data
      # Get time period from params (default to 'day')
      period = params[:period] || 'day'
      
      case period
      when 'hour'
        interval = 5.minutes
        time_span = 1.hour
        format = '%H:%M'
      when 'week'
        interval = 1.day
        time_span = 7.days
        format = '%a'
      else # 'day'
        interval = 1.hour
        time_span = 1.day
        format = '%H:%M'
      end
      
      end_time = Time.current
      start_time = end_time - time_span
      
      # Get time-series data from storage
      time_series = Storage.get_time_series_data(
        start_time: start_time,
        end_time: end_time,
        interval: interval
      )

      
      
      # Format for charts
      @volume_data = []
      @response_time_data = []
      
      # Define the minimum valid timestamp (e.g., year 2020)
      min_valid_timestamp = Time.new(1900, 1, 1)
      
      # Filter and validate time series data before processing
      valid_time_series = time_series.select do |point|
        timestamp = point[:timestamp]
        # Ensure timestamp is a Time object and is after min_valid_timestamp
        timestamp.is_a?(Time) && timestamp > min_valid_timestamp
      end
      
      # Log validation results for debugging
      invalid_count = time_series.size - valid_time_series.size
      Rails.logger.info "[RailsProfiler] Time series validation: #{time_series.size} points, #{invalid_count} invalid removed" if invalid_count > 0
      
      # Process valid data points
      valid_time_series.each do |point|
        timestamp = point[:timestamp]
        @volume_data << {
          timestamp: timestamp,
          count: point[:count] || 0
        }
        
        @response_time_data << {
          timestamp: timestamp,
          avg_duration: point[:avg_duration] || 0
        }
      end
      
      # If we have no valid data after filtering, generate sample data instead
      if @volume_data.empty?
        Rails.logger.warn "[RailsProfiler] No valid time series data found, using sample data"
        sample_data = generate_sample_time_data(6, 'count')
        @volume_data = sample_data
        @response_time_data = generate_sample_time_data(6, 'avg_duration')
      end
    end
    
    def prepare_performance_data
      # Get performance breakdown for all profiles
      @performance_data = {
        'Database' => @stats[:avg_db_time] || 0,
        'View Rendering' => @stats[:avg_view_time] || 0,
        'Ruby Code' => @stats[:avg_ruby_time] || 0
      }
      
      # Add external APIs if data exists
      if @stats[:avg_external_time] && @stats[:avg_external_time] > 0
        @performance_data['External APIs'] = @stats[:avg_external_time]
      end
      
      # Check if any other significant categories exist in profiles
      if @profiles.present?
        # Calculate "other" category if there's a gap
        total_accounted = @performance_data.values.sum
        if @stats[:avg_duration] && @stats[:avg_duration] > total_accounted
          other_time = @stats[:avg_duration] - total_accounted
          if other_time > 0 && other_time > (@stats[:avg_duration] * 0.05)
            @performance_data['Other'] = other_time
          end
        end
      end
    end
    
    def prepare_query_distribution
      # Count query types from recent profiles
      query_types = { 'SELECT' => 0, 'INSERT' => 0, 'UPDATE' => 0, 'DELETE' => 0, 'OTHER' => 0 }
      query_count = 0
      
      # Get recent profiles for analysis (limit to more recent ones for relevance)
      recent_profiles = @profiles.presence || Storage.get_profiles(limit: 100)
      
      recent_profiles.each do |profile|
        next unless profile[:queries].is_a?(Array)
        
        profile[:queries].each do |query|
          query_count += 1
          sql = query[:sql].to_s.upcase
          
          if sql.start_with?('SELECT')
            query_types['SELECT'] += 1
          elsif sql.start_with?('INSERT')
            query_types['INSERT'] += 1
          elsif sql.start_with?('UPDATE')
            query_types['UPDATE'] += 1
          elsif sql.start_with?('DELETE')
            query_types['DELETE'] += 1
          else
            query_types['OTHER'] += 1
          end
        end
      end
      
      # Only include non-zero values
      @query_data = query_types.select { |_, count| count > 0 }
      
      # If we have no query data, use sample data for visualization
      if @query_data.empty? || query_count == 0
        @query_data = nil
      end
    end
    
    def format_hotspot_data(data_hash, value_key, limit)
      data_hash.map do |name, data|
        {
          name: name,
          value: data[value_key],
          data: data
        }
      end.sort_by { |item| -item[:value] }.take(limit)
    end
    
    def prepare_flame_graph_data(profile)
      return nil unless profile && profile[:additional_data] && profile[:additional_data][:profiles].present?
      
      # Convert the code profiles into a format suitable for flame graph visualization
      code_profiles = profile[:additional_data][:profiles]
      
      # Group by method_name and calculate total time
      flame_data = []
      code_profiles.each do |method_name, data|
        # Skip methods with very small durations to avoid clutter
        next if data[:total_duration] < 1.0
        
        # Create flame graph entry
        flame_data << {
          name: method_name,
          value: data[:total_duration].round(2),
          method_type: data[:method_type] || 'ruby',
          count: data[:count]
        }
      end
      
      # Sort by duration in descending order
      flame_data.sort_by { |item| -item[:value] }
    end
    
    def prepare_call_graph_data(profile)
      return nil unless profile && profile[:additional_data] && profile[:additional_data][:call_graph].present?
      
      # Convert the call graph into a format suitable for D3 visualization
      call_graph = profile[:additional_data][:call_graph]
      
      # Format for D3 force-directed graph
      nodes = []
      links = []
      node_map = {}
      
      # Process nodes first
      call_graph.each do |caller, callees|
        unless node_map[caller]
          node_map[caller] = nodes.length
          nodes << { id: caller, name: caller.split('#').last || caller }
        end
        
        callees.each do |callee, count|
          unless node_map[callee]
            node_map[callee] = nodes.length
            nodes << { id: callee, name: callee.split('#').last || callee }
          end
          
          links << { 
            source: node_map[caller], 
            target: node_map[callee], 
            value: count 
          }
        end
      end
      
      { nodes: nodes, links: links }
    end
    
    # Helper to generate sample chart data for development
    def generate_sample_time_data(points = 6, value_key = 'count')
      period = params[:period] || 'day'
      
      case period
      when 'hour'
        interval = 10.minutes
        start_time = 1.hour.ago
      when 'week'
        interval = 1.day
        start_time = 7.days.ago
      else # 'day'
        interval = 4.hours
        start_time = 1.day.ago
      end
      
      result = []
      points.times do |i|
        timestamp = start_time + (i * interval)
        value = case value_key
                when 'count'
                  rand(10..100)
                when 'avg_duration'
                  rand(50..500)
                else
                  rand(10..100)
                end
                
        result << {
          timestamp: timestamp,
          count: value_key == 'count' ? value : rand(10..100),
          avg_duration: value_key == 'avg_duration' ? value : rand(50..500)
        }
      end
      
      result
    end
  end
end