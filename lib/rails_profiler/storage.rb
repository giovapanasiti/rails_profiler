require "redis"
require "json"

module RailsProfiler
  class Storage
    def self.store_profile(data)
      puts "[RailsProfiler] Storage.store_profile called with backend: #{RailsProfiler.config.storage_backend}"
      
      case RailsProfiler.config.storage_backend
      when :redis
        RedisStorage.store_profile(data)
      when :database
        DatabaseStorage.store_profile(data)
      end
    end

    def self.get_profiles(limit: 100, offset: 0)
      case RailsProfiler.config.storage_backend
      when :redis
        RedisStorage.get_profiles(limit: limit, offset: offset)
      when :database
        DatabaseStorage.get_profiles(limit: limit, offset: offset)
      end
    end

    def self.get_profile(request_id)
      case RailsProfiler.config.storage_backend
      when :redis
        RedisStorage.get_profile(request_id)
      when :database
        DatabaseStorage.get_profile(request_id)
      end
    end

    def self.get_summary_stats
      case RailsProfiler.config.storage_backend
      when :redis
        RedisStorage.get_summary_stats
      when :database
        DatabaseStorage.get_summary_stats
      end
    end
    
    def self.get_time_series_data(start_time:, end_time:, interval:)
      case RailsProfiler.config.storage_backend
      when :redis
        RedisStorage.get_time_series_data(start_time: start_time, end_time: end_time, interval: interval)
      when :database
        DatabaseStorage.get_time_series_data(start_time: start_time, end_time: end_time, interval: interval)
      end
    end
    
    def self.get_profiles_by_endpoint(endpoint_name, limit: 100)
      case RailsProfiler.config.storage_backend
      when :redis
        RedisStorage.get_profiles_by_endpoint(endpoint_name, limit: limit)
      when :database
        DatabaseStorage.get_profiles_by_endpoint(endpoint_name, limit: limit)
      end
    end
    
    def self.get_trends(days: 7)
      case RailsProfiler.config.storage_backend
      when :redis
        RedisStorage.get_trends(days: days)
      when :database
        DatabaseStorage.get_trends(days: days)
      end
    end
  end

  class RedisStorage
    def self.redis
      @redis ||= begin
        url = RailsProfiler.config.redis_url
        puts "[RailsProfiler] Redis: Connecting to Redis at: #{url}"
        begin
          # Simple initialization with only the URL to maximize compatibility
          # This will use our patched Redis.new method
          client = Redis.new(url: url)
          
          # If client is nil, our patched method caught an error and returned nil
          if client.nil?
            puts "[RailsProfiler] Redis: Connection failed, patched Redis.new returned nil"
            return nil
          end
          
          # Test the connection with a simple ping
          begin
            client.ping
            puts "[RailsProfiler] Redis: Successfully connected to Redis"
            client
          rescue => e
            error_type = e.class.name
            puts "[RailsProfiler] Redis: Ping test failed: #{error_type} - #{e.message}"
            puts e.backtrace.join("\n") if e.backtrace
            
            # If ping fails, disable Redis and return nil
            if defined?(RailsProfiler.config) && RailsProfiler.config.respond_to?(:disable_redis!)
              RailsProfiler.config.disable_redis!
            end
            nil
          end
        rescue => e
          error_type = e.class.name
          puts "[RailsProfiler] Redis: Connection error: #{error_type} - #{e.message}"
          puts e.backtrace.join("\n") if e.backtrace
          # Instead of raising error, return nil so we fail gracefully
          nil
        end
      end
    end

    def self.store_profile(data)
      # Skip profiles with status < 100 (WebSocket connections like /cable or /hotwire-spark)
      return if data[:status].to_i < 100
      
      # If Redis is not available, silently fail to avoid application errors
      return unless redis
      
      key = "rails_profiler:profile:#{data[:request_id]}"
      begin
        puts "[RailsProfiler] Redis: Storing profile with key: #{key}"
        redis.setex(key, retention_seconds, data.to_json)
        puts "[RailsProfiler] Redis: Adding to sorted set rails_profiler:profiles with request_id: #{data[:request_id]}"
        redis.zadd("rails_profiler:profiles", data[:started_at].to_f, data[:request_id])
        puts "[RailsProfiler] Redis: Successfully stored profile with key: #{key}"
      rescue => e
        puts "[RailsProfiler] Redis error storing profile: #{e.class.name} - #{e.message}"
        # Just log errors but don't propagate them to avoid application crashes
      end
    end

    def self.get_profiles(limit: 100, offset: 0)
      # If Redis is not available, return empty array
      return [] unless redis

      begin
        request_ids = redis.zrevrange("rails_profiler:profiles", offset, offset + limit - 1)
        profiles = request_ids.map { |id| get_profile(id) }.compact
        
        # Filter out any profiles with status < 100 (WebSocket connections like /cable or /hotwire-spark)
        # This ensures old entries don't appear in the dashboard
        profiles = profiles.reject { |p| p[:status].to_i < 100 }
        
        profiles
      rescue => e
        puts "[RailsProfiler] Redis error getting profiles: #{e.class.name} - #{e.message}"
        return []
      end
    end

    def self.get_profile(request_id)
      # If Redis is not available, return nil
      return nil unless redis

      begin
        key = "rails_profiler:profile:#{request_id}"
        data = redis.get(key)
        data ? JSON.parse(data, symbolize_names: true) : nil
      rescue => e
        puts "[RailsProfiler] Redis error getting profile: #{e.class.name} - #{e.message}"
        nil
      end
    end

    def self.get_summary_stats
      # If Redis is not available, return empty hash
      return {} unless redis
      
      begin
        total_profiles = redis.zcard("rails_profiler:profiles")
        latest_profiles = get_profiles(limit: 100)
        
        return {} if latest_profiles.empty?

        avg_duration = latest_profiles.sum { |p| p[:duration] } / latest_profiles.size
        avg_queries = latest_profiles.sum { |p| p[:query_count] } / latest_profiles.size
        avg_query_time = latest_profiles.sum { |p| p[:total_query_time] } / latest_profiles.size

        {
          total_profiles: total_profiles,
          avg_duration: avg_duration,
          avg_queries: avg_queries,
          avg_query_time: avg_query_time,
          latest_profiles: latest_profiles.first(20)
        }
      rescue => e
        puts "[RailsProfiler] Redis error getting summary stats: #{e.class.name} - #{e.message}"
        return {}
      end
    end
    
    def self.get_time_series_data(start_time:, end_time:, interval:)
      # If Redis is not available, return empty array
      return [] unless redis

      begin
        # Convert times to floats for Redis comparison
        # This fixes the TypeError with ActiveSupport::TimeWithZone
        start_time_float = start_time.to_f
        end_time_float = end_time.to_f
        
        puts "[RailsProfiler] Time series for range: #{start_time} to #{end_time} (#{start_time_float} to #{end_time_float})"
        
        # Convert interval to seconds for calculation
        interval_seconds = case interval
                          when ActiveSupport::Duration
                            interval.to_i
                          else
                            5.minutes.to_i # Default interval
                          end
                          
        # Detect if we're working with a 'day' view (1 hour intervals)
        is_day_view = interval_seconds == 1.hour.to_i

        # Log the interval we're using
        puts "[RailsProfiler] Time series using interval of #{interval_seconds} seconds (is_day_view: #{is_day_view})"

        # Get all profile IDs within the time range using Redis ZRANGEBYSCORE
        profile_ids = redis.zrangebyscore(
          "rails_profiler:profiles", 
          start_time_float, 
          end_time_float
        )
        
        puts "[RailsProfiler] Found #{profile_ids.size} profiles in time range"
        
        # Initialize buckets for time series data
        time_buckets = {}
        
        # Process each profile and group into time buckets
        profile_ids.each do |id|
          profile_data = get_profile(id)
          next unless profile_data && profile_data[:status].to_i >= 100
          
          # Ensure timestamp is a numeric value
          timestamp = profile_data[:started_at]
          
          # Convert to numeric timestamp if it's a string
          timestamp = case timestamp
                      when String
                        # Try to parse as float first, then as Time
                        begin
                          # If it's a numeric string like "1621234567.123"
                          Float(timestamp) rescue Time.parse(timestamp).to_f
                        rescue
                          # If all conversion attempts fail, use current time
                          Time.now.to_f
                        end
                      when Integer, Float
                        timestamp.to_f
                      else
                        # For any other type (including Time objects), call to_f
                        timestamp.to_f
                      end
          
          puts "[RailsProfiler] Processing profile with request_id: #{id}, timestamp: #{timestamp} (#{timestamp.class})"
          
          # Special handling for day view to ensure we bucket by hour properly
          if is_day_view
            # Parse the date and truncate to hour - ensure numeric timestamp
            time = Time.at(timestamp.to_f)
            # Create a bucket time that's aligned to the hour
            bucket_time = Time.new(time.year, time.month, time.day, time.hour).to_i
          else
            # Normal bucketing for other intervals - ensure numeric timestamp
            bucket_time = (timestamp.to_f / interval_seconds) * interval_seconds
          end
          
          # Initialize the bucket if needed
          time_buckets[bucket_time] ||= { 
            count: 0, 
            total_duration: 0, 
            total_query_count: 0, 
            total_query_time: 0 
          }
          
          # Add profile data to bucket
          time_buckets[bucket_time][:count] += 1
          time_buckets[bucket_time][:total_duration] += profile_data[:duration].to_f
          time_buckets[bucket_time][:total_query_count] += profile_data[:query_count].to_i
          time_buckets[bucket_time][:total_query_time] += profile_data[:total_query_time].to_f
        end
        
        # Fill in missing buckets in the time range
        if is_day_view
          # For day view, ensure we have all hours represented
          current_time = Time.at(start_time_float)
          end_datetime = Time.at(end_time_float)
          
          while current_time <= end_datetime
            bucket_time = Time.new(current_time.year, current_time.month, current_time.day, current_time.hour).to_i
            time_buckets[bucket_time] ||= { 
              count: 0, 
              total_duration: 0, 
              total_query_count: 0, 
              total_query_time: 0 
            }
            current_time += 1.hour
          end
        else
          # Standard interval bucketing for other views
          current_time = start_time_float.to_i
          while current_time <= end_time_float.to_i
            bucket_time = (current_time / interval_seconds) * interval_seconds
            time_buckets[bucket_time] ||= { 
              count: 0, 
              total_duration: 0, 
              total_query_count: 0, 
              total_query_time: 0 
            }
            current_time += interval_seconds
          end
        end
        
        # Convert to array format and calculate averages
        result = time_buckets.map do |timestamp, data|
          avg_duration = data[:count] > 0 ? data[:total_duration] / data[:count] : 0
          avg_query_count = data[:count] > 0 ? data[:total_query_count] / data[:count] : 0
          avg_query_time = data[:count] > 0 ? data[:total_query_time] / data[:count] : 0
          
          {
            timestamp: Time.at(timestamp),
            count: data[:count],
            avg_duration: avg_duration,
            avg_queries: avg_query_count,
            avg_query_time: avg_query_time
          }
        end
        
        # Sort by timestamp
        sorted_result = result.sort_by { |item| item[:timestamp] }
        
        puts "Time series data: #{sorted_result.inspect}"
        
        # Log for debugging
        puts "[RailsProfiler] Generated #{sorted_result.size} time buckets for chart"
        
        sorted_result
      rescue => e
        puts "[RailsProfiler] Redis error getting time series data: #{e.class.name} - #{e.message}"
        puts e.backtrace.join("\n")
        []
      end
    end

    def self.get_profiles_by_endpoint(endpoint_name, limit: 100)
      # If Redis is not available, return empty array
      return [] unless redis

      begin
        # Get all recent profiles and filter by endpoint
        all_profiles = get_profiles(limit: 500)  # Get more than we need for filtering
        
        # Filter profiles that match the requested endpoint
        matching_profiles = all_profiles.select do |profile| 
          profile[:endpoint_name] == endpoint_name
        end
        
        # Return the limited number of profiles
        matching_profiles.take(limit)
      rescue => e
        puts "[RailsProfiler] Redis error getting profiles by endpoint: #{e.class.name} - #{e.message}"
        []
      end
    end
    
    def self.get_trends(days: 7)
      # If Redis is not available, return empty array
      return [] unless redis

      begin
        # Calculate time range
        end_time = Time.current
        start_time = days.days.ago.beginning_of_day
        
        # Get all profile IDs within the time range using Redis ZRANGEBYSCORE
        profile_ids = redis.zrangebyscore(
          "rails_profiler:profiles", 
          start_time.to_f, 
          end_time.to_f
        )
        
        puts "[RailsProfiler] Found #{profile_ids.size} profiles for trends in #{days} day period"
        
        # Group profiles by hour
        hourly_data = {}
        
        # Process each profile
        profile_ids.each do |id|
          profile_data = get_profile(id)
          next unless profile_data && profile_data[:status].to_i >= 100
          
          # Ensure timestamp is a numeric value and convert to Time object
          timestamp = profile_data[:started_at]
          time_obj = case timestamp
                     when String
                       # Try to parse as float first, then as Time
                       begin
                         # Try to parse as float first, then as Time
                         begin
                           float_timestamp = Float(timestamp)
                           Time.at(float_timestamp)
                         rescue
                           # If float conversion fails, try parsing as Time
                           Time.at(Time.parse(timestamp).to_f)
                         end
                       rescue
                         # If all conversion attempts fail, use current time
                         Time.now
                       end
                     when Integer, Float
                       Time.at(timestamp)
                     else
                       # For any other type (including Time objects), convert to time
                       Time.at(timestamp.to_f)
                     end
          
          # Get the hour bucket (round down to the hour)
          hour_key = time_obj.beginning_of_hour.to_i
          
          # Initialize the hour bucket if needed
          hourly_data[hour_key] ||= { 
            count: 0, 
            total_duration: 0
          }
          
          # Add profile data to the hour bucket
          hourly_data[hour_key][:count] += 1
          hourly_data[hour_key][:total_duration] += profile_data[:duration].to_f
        end
        
        # Fill in missing hours in the time range
        current_hour = start_time.beginning_of_hour.to_i
        end_hour = end_time.beginning_of_hour.to_i
        
        while current_hour <= end_hour
          hourly_data[current_hour] ||= { 
            count: 0, 
            total_duration: 0
          }
          current_hour += 1.hour.to_i
        end
        
        # Convert to array format for the charts
        result = hourly_data.map do |timestamp, data|
          avg_duration = data[:count] > 0 ? data[:total_duration] / data[:count] : 0
          
          {
            timestamp: timestamp * 1000, # Convert to milliseconds for JS charts
            count: data[:count],
            avg_duration: avg_duration
          }
        end
        
        # Sort by timestamp
        sorted_result = result.sort_by { |item| item[:timestamp] }
        
        puts "[RailsProfiler] Generated #{sorted_result.size} hourly data points for trends"
        
        sorted_result
      rescue => e
        puts "[RailsProfiler] Redis error getting trends: #{e.class.name} - #{e.message}"
        puts e.backtrace.join("\n")
        []
      end
    end

    private

    def self.retention_seconds
      days = RailsProfiler.config.retention_days
      seconds = days * 24 * 60 * 60
      puts "[RailsProfiler] Redis: Using retention period of #{days} days (#{seconds} seconds)"
      seconds
    end
  end

  class DatabaseStorage
    def self.store_profile(data)
      # Skip profiles with status < 100 (WebSocket connections like /cable or /hotwire-spark)
      return if data[:status].to_i < 100
      
      # Convert data hash to a format suitable for database storage
      profile_data = {
        request_id: data[:request_id],
        url: data[:url],
        method: data[:method],
        path: data[:path],
        controller: data[:controller],
        action: data[:action],
        endpoint_name: data[:endpoint_name],
        format: data[:format],
        status: data[:status],
        duration: data[:duration],
        query_count: data[:query_count],
        total_query_time: data[:total_query_time],
        view_time: data[:view_time],
        db_time: data[:db_time],
        ruby_time: data[:ruby_time],
        started_at: data[:started_at],
        queries: data[:queries].to_json,
        segments: data[:segments].to_json,
        additional_data: data[:additional_data].to_json
      }

      # Find existing record or create new one
      profile = Profile.find_or_initialize_by(request_id: data[:request_id])
      profile.update!(profile_data)
    end

    def self.get_profiles(limit: 100, offset: 0)
      Profile.where("status >= 100")
             .order(started_at: :desc)
             .limit(limit)
             .offset(offset)
             .map do |profile|
        # Convert database record back to the format expected by the application
        {
          request_id: profile.request_id,
          url: profile.url,
          method: profile.method,
          path: profile.path,
          controller: profile.controller,
          action: profile.action,
          endpoint_name: profile.endpoint_name,
          format: profile.format,
          status: profile.status,
          duration: profile.duration,
          query_count: profile.query_count,
          total_query_time: profile.total_query_time,
          view_time: profile.view_time,
          db_time: profile.db_time,
          ruby_time: profile.ruby_time,
          started_at: profile.started_at,
          queries: JSON.parse(profile.queries, symbolize_names: true),
          segments: JSON.parse(profile.segments, symbolize_names: true),
          additional_data: JSON.parse(profile.additional_data, symbolize_names: true)
        }
      end
    end

    def self.get_profile(request_id)
      profile = Profile.find_by(request_id: request_id)
      return nil unless profile

      # Convert database record to the format expected by the application
      {
        request_id: profile.request_id,
        url: profile.url,
        method: profile.method,
        path: profile.path,
        controller: profile.controller,
        action: profile.action,
        endpoint_name: profile.endpoint_name,
        format: profile.format,
        status: profile.status,
        duration: profile.duration,
        query_count: profile.query_count,
        total_query_time: profile.total_query_time,
        view_time: profile.view_time,
        db_time: profile.db_time,
        ruby_time: profile.ruby_time,
        started_at: profile.started_at,
        queries: JSON.parse(profile.queries, symbolize_names: true),
        segments: JSON.parse(profile.segments, symbolize_names: true),
        additional_data: JSON.parse(profile.additional_data, symbolize_names: true)
      }
    end

    def self.get_summary_stats
      # Use filtered count for consistency with Redis implementation
      total_profiles = Profile.where("status >= 100").count
      latest_profiles = get_profiles(limit: 50)
      
      return {} if latest_profiles.empty?
      
      # Aggregate endpoints like Skylight does
      endpoints = aggregate_endpoints

      # Calculate averages based on filtered profiles
      avg_duration = Profile.where("status >= 100").average(:duration).to_f
      avg_queries = Profile.where("status >= 100").average(:query_count).to_f
      avg_query_time = Profile.where("status >= 100").average(:total_query_time).to_f

      {
        total_profiles: total_profiles,
        avg_duration: avg_duration,
        avg_queries: avg_queries,
        avg_query_time: avg_query_time,
        endpoints: endpoints,
        latest_profiles: latest_profiles
      }
    end
    
    # Similar to Skylight's endpoint aggregation
    def self.aggregate_endpoints
      # Group by endpoint_name and get performance metrics, filtering out status < 100
      endpoint_stats = Profile.where.not(endpoint_name: nil)
                              .where("status >= 100")
                              .group(:endpoint_name)
                              .select(
                                "endpoint_name, 
                                COUNT(*) as request_count, 
                                AVG(duration) as avg_duration, 
                                MAX(duration) as max_duration,
                                AVG(db_time) as avg_db_time,
                                AVG(view_time) as avg_view_time,
                                AVG(ruby_time) as avg_ruby_time"
                              )
                              
      # Convert to the format needed for the UI
      endpoints = endpoint_stats.map do |stat|
        {
          name: stat.endpoint_name,
          count: stat.request_count,
          avg_duration: stat.avg_duration,
          max_duration: stat.max_duration,
          avg_db_time: stat.avg_db_time,
          avg_view_time: stat.avg_view_time,
          avg_ruby_time: stat.avg_ruby_time,
          # Calculate percentages for the segments visualization
          segments: [
            { name: "Database", percentage: (stat.avg_db_time / stat.avg_duration) * 100, color: "blue" },
            { name: "View", percentage: (stat.avg_view_time / stat.avg_duration) * 100, color: "green" },
            { name: "Ruby", percentage: (stat.avg_ruby_time / stat.avg_duration) * 100, color: "purple" }
          ]
        }
      end
      
      # Sort by average duration (slowest first)
      endpoints.sort_by { |e| -e[:avg_duration] }
    end
    
    # Get time-series data for trend charts
    def self.get_trends(days: 7)
      start_date = days.days.ago.beginning_of_day
      
      # Group by hour and count requests
      hourly_counts = Profile.where("started_at >= ?", start_date)
                            .group("date_trunc('hour', started_at)")
                            .count
                            
      # Calculate average durations by hour
      hourly_durations = Profile.where("started_at >= ?", start_date)
                               .group("date_trunc('hour', started_at)")
                               .average(:duration)
                               
      # Merge into a single dataset for charting
      hourly_data = []
      
      # Combine counts and durations
      (start_date.to_i..Time.current.to_i).step(1.hour) do |timestamp|
        datetime = Time.at(timestamp)
        hour_key = datetime.utc.change(min: 0, sec: 0)
        
        hourly_data << {
          timestamp: datetime.to_i * 1000, # Convert to milliseconds for JS charts
          count: hourly_counts[hour_key] || 0,
          avg_duration: hourly_durations[hour_key] || 0
        }
      end
      
      hourly_data
    end
    
    # Helper method to clean up old profiles based on retention days
    # Returns the number of deleted profiles
    def self.cleanup_old_profiles
      retention_date = RailsProfiler.config.retention_days.days.ago
      Profile.where('started_at < ?', retention_date).delete_all
    end
    
    def self.get_time_series_data(start_time:, end_time:, interval:)
      begin
        # Convert interval to seconds for calculation
        interval_seconds = case interval
                          when ActiveSupport::Duration
                            interval.to_i
                          else
                            5.minutes.to_i # Default interval
                          end
        
        # Query all profiles within the time range
        profiles = Profile.where("started_at >= ? AND started_at <= ?", start_time, end_time)
                          .where("status >= 100")
                          .select(:started_at, :duration, :query_count, :total_query_time)
        
        # Group profiles by time buckets
        time_buckets = {}
        
        profiles.each do |profile|
          # Calculate the bucket timestamp (floor to the nearest interval)
          bucket_time = (profile.started_at.to_i / interval_seconds) * interval_seconds
          
          # Initialize the bucket if needed
          time_buckets[bucket_time] ||= { 
            count: 0, 
            total_duration: 0, 
            total_query_count: 0, 
            total_query_time: 0 
          }
          
          # Add profile data to the bucket
          time_buckets[bucket_time][:count] += 1
          time_buckets[bucket_time][:total_duration] += profile.duration
          time_buckets[bucket_time][:total_query_count] += profile.query_count
          time_buckets[bucket_time][:total_query_time] += profile.total_query_time
        end
        
        # Fill in any missing buckets in the range
        current_time = start_time.to_i
        while current_time <= end_time.to_i
          time_buckets[current_time] ||= { 
            count: 0, 
            total_duration: 0, 
            total_query_count: 0, 
            total_query_time: 0 
          }
          current_time += interval_seconds
        end
        
        # Convert to array and sort by timestamp
        result = time_buckets.map do |timestamp, data|
          avg_duration = data[:count] > 0 ? data[:total_duration] / data[:count] : 0
          avg_query_count = data[:count] > 0 ? data[:total_query_count] / data[:count] : 0
          avg_query_time = data[:count] > 0 ? data[:total_query_time] / data[:count] : 0
          
          {
            timestamp: Time.at(timestamp),
            count: data[:count],
            avg_duration: avg_duration,
            avg_queries: avg_query_count,
            avg_query_time: avg_query_time
          }
        end
        
        result.sort_by { |item| item[:timestamp] }
      rescue => e
        puts "[RailsProfiler] Database error getting time series data: #{e.class.name} - #{e.message}"
        puts e.backtrace.join("\n")
        return []
      end
    end
    
    def self.get_profiles_by_endpoint(endpoint_name, limit: 100)
      begin
        profiles = Profile.where(endpoint_name: endpoint_name)
                          .where("status >= 100")
                          .order(started_at: :desc)
                          .limit(limit)
                          .map do |profile|
          # Convert database record to the format expected by the application
          {
            request_id: profile.request_id,
            url: profile.url,
            method: profile.method,
            path: profile.path,
            controller: profile.controller,
            action: profile.action,
            endpoint_name: profile.endpoint_name,
            format: profile.format,
            status: profile.status,
            duration: profile.duration,
            query_count: profile.query_count,
            total_query_time: profile.total_query_time,
            view_time: profile.view_time,
            db_time: profile.db_time,
            ruby_time: profile.ruby_time,
            started_at: profile.started_at,
            queries: JSON.parse(profile.queries, symbolize_names: true),
            segments: JSON.parse(profile.segments, symbolize_names: true),
            additional_data: JSON.parse(profile.additional_data, symbolize_names: true)
          }
        end
        
        profiles
      rescue => e
        puts "[RailsProfiler] Database error getting profiles by endpoint: #{e.class.name} - #{e.message}"
        []
      end
    end
  end
end
