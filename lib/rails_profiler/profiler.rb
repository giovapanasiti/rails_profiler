module RailsProfiler
  class Profiler
    attr_reader :request_id, :started_at, :queries, :segments, :url, :method, :path, :format
    attr_accessor :controller, :action, :endpoint_name, :code_profiles

    def initialize(request_id, url: nil, method: nil, path: nil, format: nil)
      @request_id = request_id
      @started_at = Time.current
      @queries = []
      @segments = []
      @events = [] # For timeline generation
      @code_profiles = [] # For code bottleneck tracking
      @url = url
      @method = method
      @path = path
      @format = format
      
      # Track time spent in different parts of the request
      @view_time = 0
      @db_time = 0
      @ruby_time = 0
      @controller_time = 0
      
      # Track hotspots
      @hotspots = {
        controllers: {},
        models: {},
        views: {},
        methods: {}
      }
      
      # Start tracking framework events for timeline
      subscribe_to_events
    end

    def add_query(query_data)
      @queries << query_data
      # Track time spent in database
      @db_time += query_data[:duration] || 0
      
      # Track if this query is associated with a model
      if query_data[:name]&.include?(' Load')
        model_name = query_data[:name].split(' ')[0]
        @hotspots[:models][model_name] ||= { count: 0, total_time: 0 }
        @hotspots[:models][model_name][:count] += 1
        @hotspots[:models][model_name][:total_time] += query_data[:duration] || 0
      end
    end
    
    def add_code_profile(profile_data)
      @code_profiles << profile_data
      
      # Track code hotspots
      if profile_data[:name].include?('Controller')
        controller_name = profile_data[:name].split('#').first
        action_name = profile_data[:method_name]
        
        # Track controller time
        @hotspots[:controllers][controller_name] ||= { 
          actions: {}, 
          total_time: 0 
        }
        
        @hotspots[:controllers][controller_name][:total_time] += profile_data[:duration]
        
        # Track action time
        @hotspots[:controllers][controller_name][:actions][action_name] ||= {
          count: 0,
          total_time: 0
        }
        
        @hotspots[:controllers][controller_name][:actions][action_name][:count] += 1
        @hotspots[:controllers][controller_name][:actions][action_name][:total_time] += profile_data[:duration]
        
        @controller_time += profile_data[:duration]
      else
        # Track general method hotspots
        method_key = profile_data[:name]
        @hotspots[:methods][method_key] ||= { count: 0, total_time: 0, exclusive_time: 0 }
        @hotspots[:methods][method_key][:count] += 1
        @hotspots[:methods][method_key][:total_time] += profile_data[:duration]
        @hotspots[:methods][method_key][:exclusive_time] += profile_data[:exclusive_duration]
      end
    end
    
    def add_event(event_data)
      @events << event_data
      
      # Track view rendering hotspots - use the full template path instead of just the filename
      if event_data[:category] == 'view'
        # Extract the full identifier path from the event name if available
        if event_data[:name].to_s.start_with?('Render ') && event_data[:identifier].present?
          view_path = event_data[:identifier]
          
          # Make the path relative to the app root if possible for cleaner presentation
          if defined?(Rails.root) && view_path.start_with?(Rails.root.to_s)
            view_path = view_path.sub(Rails.root.to_s, '')
          end
          
          # Create or update the view in the hotspots collection
          @hotspots[:views][view_path] ||= { count: 0, total_time: 0 }
          @hotspots[:views][view_path][:count] += 1
          @hotspots[:views][view_path][:total_time] += event_data[:duration]
        else
          # Fallback to the existing behavior if we can't get the full path
          view_name = event_data[:name].to_s.split(' ').last
          @hotspots[:views][view_name] ||= { count: 0, total_time: 0 }
          @hotspots[:views][view_name][:count] += 1
          @hotspots[:views][view_name][:total_time] += event_data[:duration]
        end
      end
    end
    
    # Get child methods for a given method to build call graph
    def child_methods(method_name)
      @code_profiles.select { |p| p[:parent] == method_name }
    end

    def add_controller_info(controller:, action:)
      @controller = controller
      @action = action
      # Normalize endpoint name like Skylight does (Controller#action)
      @endpoint_name = "#{controller.sub(/Controller$/, '')}##{action}"
    end
    
    def process_segments(total_duration)
      # Convert events into timeline segments
      process_events_into_segments
      
      # Calculate ruby time (total time minus db and view time and controller time)
      @ruby_time = total_duration - @db_time - @view_time - @controller_time
      @ruby_time = 0 if @ruby_time < 0 # Ensure we don't have negative time
      
      # Create segment percentages for visualization
      db_percentage = (@db_time / total_duration) * 100 rescue 0
      view_percentage = (@view_time / total_duration) * 100 rescue 0
      controller_percentage = (@controller_time / total_duration) * 100 rescue 0
      ruby_percentage = (@ruby_time / total_duration) * 100 rescue 0
      
      # Add top-level segments for the timeline view
      @segments << { name: "Database", duration: @db_time, percentage: db_percentage, color: "#3498DB" }
      @segments << { name: "View", duration: @view_time, percentage: view_percentage, color: "#2ECC71" }
      @segments << { name: "Controller", duration: @controller_time, percentage: controller_percentage, color: "#E67E22" }
      @segments << { name: "Ruby", duration: @ruby_time, percentage: ruby_percentage, color: "#9B59B6" }
    end

    def finish(status, duration = nil)

      return if status < 100

      total_duration = duration || calculate_duration
      query_count = @queries.size
      total_query_time = @queries.sum { |q| q[:duration] || 0 }
      
      # Build call graph for visualization
      call_graph = build_call_graph
      
      # Get top hotspots for quick access
      top_hotspots = {
        controllers: top_items_from_hash(@hotspots[:controllers], :total_time, 5),
        methods: top_items_from_hash(@hotspots[:methods], :exclusive_time, 10),
        models: top_items_from_hash(@hotspots[:models], :total_time, 5),
        views: top_items_from_hash(@hotspots[:views], :total_time, 5)
      }

      
      
      data = {
        request_id: @request_id,
        url: @url,
        method: @method,
        path: @path,
        controller: @controller,
        action: @action,
        endpoint_name: @endpoint_name,
        format: @format,
        status: status,
        started_at: @started_at,
        duration: total_duration,
        query_count: query_count,
        total_query_time: total_query_time,
        view_time: @view_time,
        db_time: @db_time,
        controller_time: @controller_time,
        ruby_time: @ruby_time,
        queries: @queries,
        segments: @segments,
        additional_data: { 
          events: @events,
          profiles: @code_profiles,
          call_graph: call_graph,
          hotspots: top_hotspots
        }
      }

      Storage.store_profile(data)
    end
    
    def add_code_profile(data)
      method_name = data[:name]
      
      # Create or update the code profile
      if @code_profiles[method_name]
        existing = @code_profiles[method_name]
        existing[:count] += 1
        existing[:total_duration] += data[:duration]
        existing[:max_duration] = [existing[:max_duration], data[:duration]].max
        existing[:min_duration] = [existing[:min_duration], data[:duration]].min
        
        # Track memory if available
        if data[:memory_delta]
          existing[:total_memory_delta] ||= 0
          existing[:total_memory_delta] += data[:memory_delta]
          existing[:max_memory_delta] = [existing[:max_memory_delta] || 0, data[:memory_delta]].max
        end
      else
        @code_profiles[method_name] = {
          name: method_name,
          method_name: data[:method_name],
          method_type: data[:method_type],
          file_path: data[:file_path],
          line_number: data[:line_number],
          count: 1,
          total_duration: data[:duration],
          max_duration: data[:duration],
          min_duration: data[:duration],
          exclusive_duration: data[:exclusive_duration] || data[:duration],
          total_memory_delta: data[:memory_delta],
          max_memory_delta: data[:memory_delta],
          backtrace: data[:backtrace]
        }
      end
      
      # Build call graph
      if data[:parent]
        @call_graph[data[:parent]] ||= {}
        @call_graph[data[:parent]][method_name] ||= 0
        @call_graph[data[:parent]][method_name] += 1
        
        @call_counts[method_name] ||= 0
        @call_counts[method_name] += 1
      end
    end
    
    def add_query_profile(data)
      @query_profiles << data.merge(
        started_at: data[:started_at] || Process.clock_gettime(Process::CLOCK_MONOTONIC)
      )
    end
    
    def prepare_code_profiles
      # Convert code_profiles hash to array and calculate average durations
      @code_profiles.values.map do |profile|
        profile[:avg_duration] = profile[:total_duration] / profile[:count]
        profile[:avg_memory_delta] = profile[:total_memory_delta] / profile[:count] if profile[:total_memory_delta]
        
        # Calculate percentage of total time
        profile[:percent_of_total] = (profile[:total_duration] / @total_duration) * 100
        
        profile
      end
    end
    
    def controller_hotspots
      prepare_code_profiles.select { |p| p[:method_type] == 'controller' }
                            .sort_by { |p| -p[:total_duration] }
    end
    
    def method_hotspots(limit = 10)
      prepare_code_profiles.sort_by { |p| -p[:total_duration] }
                           .first(limit)
    end
    
    def memory_hotspots(limit = 10)
      prepare_code_profiles.select { |p| p[:total_memory_delta] }
                           .sort_by { |p| -p[:total_memory_delta].to_i }
                           .first(limit)
    end
    
    def model_hotspots(limit = 10)
      prepare_code_profiles.select { |p| p[:method_type] == 'model' }
                           .sort_by { |p| -p[:total_duration] }
                           .first(limit)
    end
    
    def view_hotspots(limit = 10)
      prepare_code_profiles.select { |p| p[:method_type] == 'view' }
                           .sort_by { |p| -p[:total_duration] }
                           .first(limit)
    end
    
    def flame_graph_data
      # Generate flame graph data structure
      nodes = {}
      links = []
      
      # Create nodes for each method
      prepare_code_profiles.each do |profile|
        nodes[profile[:name]] = {
          id: profile[:name],
          name: profile[:name],
          value: profile[:total_duration].round(2),
          count: profile[:count],
          type: profile[:method_type]
        }
      end
      
      # Create links between methods
      @call_graph.each do |parent, children|
        children.each do |child, count|
          links << {
            source: parent,
            target: child,
            value: count
          }
        end
      end
      
      { nodes: nodes.values, links: links }
    end
    
    private
    
    def calculate_duration
      (Time.current - @started_at) * 1000 # in milliseconds
    end
    
    def subscribe_to_events
      # Subscribe to ActiveSupport notifications for timeline tracking
      @subscribers = []
      
      # Track view rendering time
      @subscribers << ActiveSupport::Notifications.subscribe("render_template.action_view") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        @view_time += event.duration
        add_event({
          name: "Render #{event.payload[:identifier]&.split('/')&.last}",
          category: "view",
          start: event.time.to_f,
          finish: event.end.to_f,
          duration: event.duration,
          identifier: event.payload[:identifier] # Add the full template path
        })
      end
      
      # Track partial rendering
      @subscribers << ActiveSupport::Notifications.subscribe("render_partial.action_view") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        @view_time += event.duration
        add_event({
          name: "Render partial #{event.payload[:identifier]&.split('/')&.last}",
          category: "view",
          start: event.time.to_f,
          finish: event.end.to_f,
          duration: event.duration,
          identifier: event.payload[:identifier] # Add the full template path
        })
      end
      
      # Track action controller events
      @subscribers << ActiveSupport::Notifications.subscribe("process_action.action_controller") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        # Update controller time counter
        @controller_time += event.duration
        add_event({
          name: "Controller action",
          category: "controller",
          start: event.time.to_f,
          finish: event.end.to_f,
          duration: event.duration,
          details: "#{event.payload[:controller]}##{event.payload[:action]}"
        })
      end
    end
    
    def process_events_into_segments
      # Convert raw events into structured segments for visualization
      @events.sort_by { |e| e[:start] }.each do |event|
        case event[:category]
        when "view"
          @segments << {
            name: event[:name],
            duration: event[:duration],
            category: "view",
            color: "#2ECC71"
          }
        when "controller"
          @segments << {
            name: event[:name],
            duration: event[:duration],
            category: "controller", 
            details: event[:details],
            color: "#E67E22"
          }
        end
      end
    end
    
    # Build a call graph for flame graph visualization
    def build_call_graph
      # Create a hierarchical structure of method calls
      root_nodes = @code_profiles.select { |p| p[:parent].nil? }
      
      root_nodes.map do |node|
        build_node(node)
      end
    end
    
    def build_node(profile)
      children = @code_profiles.select { |p| p[:parent] == profile[:name] }
      
      {
        name: profile[:name],
        method_name: profile[:method_name],
        duration: profile[:duration],
        exclusive_duration: profile[:exclusive_duration],
        file_path: profile[:file_path],
        line_number: profile[:line_number],
        children: children.map { |child| build_node(child) }
      }
    end
    
    # Extract top items from a hash based on a specific value key
    def top_items_from_hash(hash, value_key, limit)
      # For views, make sure we're using the full path as the name
      hash.map do |key, data|
        {
          name: key,   # This is the full template path when coming from @hotspots[:views]
          value: data[value_key],
          data: data
        }
      end.sort_by { |item| -item[:value] }.take(limit)
    end
  end
end