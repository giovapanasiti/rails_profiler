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
  end

  class RedisStorage
    def self.redis
      @redis ||= begin
        url = RailsProfiler.config.redis_url
        puts "[RailsProfiler] Redis: Connecting to Redis at: #{url}"
        begin
          # Simple initialization without any extra options to maximize compatibility
          client = Redis.new(url: url)
          # Test the connection
          client.ping
          puts "[RailsProfiler] Redis: Successfully connected to Redis"
          client
        rescue => e
          puts "[RailsProfiler] Redis: Connection error: #{e.class.name} - #{e.message}"
          puts e.backtrace.join("\n")
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
  end
end
