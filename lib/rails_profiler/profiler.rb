module RailsProfiler
  class Profiler
    attr_reader :request_id, :started_at, :queries, :profiles

    def initialize(request_id)
      @request_id = request_id
      @started_at = Time.current
      @queries = []
      @profiles = []
    end

    def add_query(query_data)
      @queries << query_data
    end

    def add_profile(profile_data)
      @profiles << profile_data
    end

    def finish(response_status)
      data = {
        request_id: @request_id,
        started_at: @started_at,
        ended_at: Time.current,
        duration: (Time.current - @started_at) * 1000, # in milliseconds
        response_status: response_status,
        queries: @queries,
        profiles: @profiles,
        query_count: @queries.size,
        total_query_time: @queries.sum { |q| q[:duration] },
        created_at: Time.current
      }

      Storage.store_profile(data)
    end
  end
end