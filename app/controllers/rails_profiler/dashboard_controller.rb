module RailsProfiler
  class DashboardController < ApplicationController
    def index
      @stats = Storage.get_summary_stats
      @profiles = @stats[:latest_profiles] || []
      @endpoints = @stats[:endpoints] || []
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
      
      # Aggregate hotspot data from all profiles
      @profiles.each do |profile|
        if profile[:additional_data].is_a?(Hash) && 
           profile[:additional_data][:hotspots].is_a?(Hash)
          
          # Merge controller hotspots
          profile_hotspots = profile[:additional_data][:hotspots]
          
          # Aggregate controller hotspots
          if profile_hotspots[:controllers].is_a?(Array)
            profile_hotspots[:controllers].each do |controller|
              name = controller[:name]
              hotspots[:controllers][name] ||= { total_time: 0, count: 0, actions: {} }
              hotspots[:controllers][name][:total_time] += controller[:value]
              hotspots[:controllers][name][:count] += 1
              
              if controller[:data][:actions].is_a?(Hash)
                controller[:data][:actions].each do |action, action_data|
                  hotspots[:controllers][name][:actions][action] ||= { total_time: 0, count: 0 }
                  hotspots[:controllers][name][:actions][action][:total_time] += action_data[:total_time]
                  hotspots[:controllers][name][:actions][action][:count] += action_data[:count]
                end
              end
            end
          end
          
          # Aggregate method hotspots
          if profile_hotspots[:methods].is_a?(Array)
            profile_hotspots[:methods].each do |method|
              name = method[:name]
              hotspots[:methods][name] ||= { exclusive_time: 0, total_time: 0, count: 0 }
              hotspots[:methods][name][:exclusive_time] += method[:value]
              hotspots[:methods][name][:total_time] += method[:data][:total_time]
              hotspots[:methods][name][:count] += method[:data][:count]
            end
          end
          
          # Aggregate model hotspots
          if profile_hotspots[:models].is_a?(Array)
            profile_hotspots[:models].each do |model|
              name = model[:name]
              hotspots[:models][name] ||= { total_time: 0, count: 0 }
              hotspots[:models][name][:total_time] += model[:value]
              hotspots[:models][name][:count] += model[:data][:count]
            end
          end
          
          # Aggregate view hotspots
          if profile_hotspots[:views].is_a?(Array)
            profile_hotspots[:views].each do |view|
              name = view[:name]
              hotspots[:views][name] ||= { total_time: 0, count: 0 }
              hotspots[:views][name][:total_time] += view[:value]
              hotspots[:views][name][:count] += view[:data][:count]
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
      
      # Get maximum times for scaling progress bars
      @max_controller_time = @hotspots[:controllers].first[:value] rescue 100
      @max_method_time = @hotspots[:methods].first[:value] rescue 100
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
  end
end