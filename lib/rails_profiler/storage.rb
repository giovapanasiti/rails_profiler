require "redis"
require "json"

module RailsProfiler
  class Storage
    def self.store_profile(data)
      Rails.logger.debug "[RailsProfiler] Storage.store_profile called with backend: #{RailsProfiler.config.storage_backend}"
      puts "Storing profile with request_id: #{data[:request_id]}, path: #{data[:path]}, duration: #{data[:duration].round(2)}ms"

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
        Rails.logger.debug "[RailsProfiler] Connecting to Redis at: #{RailsProfiler.config.redis_url}"
        Redis.new(url: RailsProfiler.config.redis_url)
      end
    end

    def self.store_profile(data)
      key = "rails_profiler:profile:#{data[:request_id]}"
      puts "Storing profile in Redis with key: #{key}, data: #{data}"
      begin
        Rails.logger.debug "[RailsProfiler] Redis: storing profile with key: #{key}, expiry: #{retention_seconds} seconds"
        redis.setex(key, retention_seconds, data.to_json)
        Rails.logger.debug "[RailsProfiler] Redis: adding to sorted set rails_profiler:profiles with score: #{data[:started_at].to_f}"
        redis.zadd("rails_profiler:profiles", data[:started_at].to_f, data[:request_id])
        Rails.logger.info "[RailsProfiler] Redis: profile successfully stored with key: #{key}"
      rescue => e
        Rails.logger.error "[RailsProfiler] Redis error storing profile: #{e.class.name} - #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end
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
      Rails.logger.debug "[RailsProfiler] Redis retention configured for #{RailsProfiler.config.retention_days} days"
      RailsProfiler.config.retention_days * 24 * 60 * 60
    end
  end

  class DatabaseStorage
    def self.store_profile(data)
      # Convert data hash to a format suitable for database storage
      profile_data = {
        request_id: data[:request_id],
        url: data[:url],
        method: data[:method],
        path: data[:path],
        format: data[:format],
        status: data[:status],
        duration: data[:duration],
        query_count: data[:query_count],
        total_query_time: data[:total_query_time],
        started_at: data[:started_at],
        queries: data[:queries].to_json,
        additional_data: data[:additional_data].to_json
      }

      # Find existing record or create new one
      profile = Profile.find_or_initialize_by(request_id: data[:request_id])
      profile.update!(profile_data)
    end

    def self.get_profiles(limit: 100, offset: 0)
      Profile.order(started_at: :desc).limit(limit).offset(offset).map do |profile|
        # Convert database record back to the format expected by the application
        {
          request_id: profile.request_id,
          url: profile.url,
          method: profile.method,
          path: profile.path,
          format: profile.format,
          status: profile.status,
          duration: profile.duration,
          query_count: profile.query_count,
          total_query_time: profile.total_query_time,
          started_at: profile.started_at,
          queries: JSON.parse(profile.queries, symbolize_names: true),
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
        format: profile.format,
        status: profile.status,
        duration: profile.duration,
        query_count: profile.query_count,
        total_query_time: profile.total_query_time,
        started_at: profile.started_at,
        queries: JSON.parse(profile.queries, symbolize_names: true),
        additional_data: JSON.parse(profile.additional_data, symbolize_names: true)
      }
    end

    def self.get_summary_stats
      total_profiles = Profile.count
      latest_profiles = get_profiles(limit: 100)
      
      return {} if latest_profiles.empty?

      avg_duration = Profile.average(:duration).to_f
      avg_queries = Profile.average(:query_count).to_f
      avg_query_time = Profile.average(:total_query_time).to_f

      {
        total_profiles: total_profiles,
        avg_duration: avg_duration,
        avg_queries: avg_queries,
        avg_query_time: avg_query_time,
        latest_profiles: latest_profiles.first(20)
      }
    end
    
    # Helper method to clean up old profiles based on retention days
    # Returns the number of deleted profiles
    def self.cleanup_old_profiles
      retention_date = RailsProfiler.config.retention_days.days.ago
      Profile.where('started_at < ?', retention_date).delete_all
    end
  end
end
