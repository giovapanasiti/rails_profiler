require "redis"
require "json"

module RailsProfiler
  class Storage
    def self.store_profile(data)
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
      @redis ||= Redis.new(url: RailsProfiler.config.redis_url)
    end

    def self.store_profile(data)
      key = "rails_profiler:profile:#{data[:request_id]}"
      redis.setex(key, retention_seconds, data.to_json)
      redis.zadd("rails_profiler:profiles", data[:started_at].to_f, data[:request_id])
    end

    def self.get_profiles(limit: 100, offset: 0)
      request_ids = redis.zrevrange("rails_profiler:profiles", offset, offset + limit - 1)
      profiles = request_ids.map { |id| get_profile(id) }.compact
      profiles
    end

    def self.get_profile(request_id)
      key = "rails_profiler:profile:#{request_id}"
      data = redis.get(key)
      data ? JSON.parse(data, symbolize_names: true) : nil
    end

    def self.get_summary_stats
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
    end

    private

    def self.retention_seconds
      RailsProfiler.config.retention_days * 24 * 60 * 60
    end
  end

  class DatabaseStorage
    # Implementation for database storage would go here
    # This would use ActiveRecord models
  end
end
