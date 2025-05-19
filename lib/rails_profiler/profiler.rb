module RailsProfiler
  class Profiler
    attr_reader :request_id, :started_at, :queries, :profiles, :url, :method, :path, :format

    def initialize(request_id, url: nil, method: nil, path: nil, format: nil)
      @request_id = request_id
      @started_at = Time.current
      @queries = []
      @profiles = []
      @url = url
      @method = method
      @path = path
      @format = format
      Rails.logger.debug "[RailsProfiler] Profiler initialized with request_id: #{request_id}, path: #{path}"
    end

    def add_query(query_data)
      @queries << query_data
      Rails.logger.debug "[RailsProfiler] Query added to profile, total queries: #{@queries.size}" if @queries.size % 5 == 0
    end

    def add_profile(profile_data)
      @profiles << profile_data
      Rails.logger.debug "[RailsProfiler] Profile data added: #{profile_data[:name]}"
    end

    def finish(status)
      Rails.logger.info "[RailsProfiler] Finishing profile for request_id: #{@request_id}, queries: #{@queries.size}"
      
      data = {
        request_id: @request_id,
        url: @url,
        method: @method,
        path: @path,
        format: @format,
        status: status,
        started_at: @started_at,
        ended_at: Time.current,
        duration: (Time.current - @started_at) * 1000, # in milliseconds
        queries: @queries,
        query_count: @queries.size,
        total_query_time: @queries.sum { |q| q[:duration] || 0 },
        additional_data: { profiles: @profiles }
      }

      Rails.logger.info "[RailsProfiler] About to store profile with data: request_id=#{data[:request_id]}, path=#{data[:path]}, duration=#{data[:duration].round(2)}ms"
      
      # begin
        Storage.store_profile(data)
        Rails.logger.info "[RailsProfiler] Profile successfully stored"
      # rescue => e
      #   Rails.logger.error "[RailsProfiler] Error storing profile: #{e.class.name} - #{e.message}"
      #   Rails.logger.error e.backtrace.join("\n")
      # end
    end
  end
end