module RailsProfiler
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :exception
    before_action :authenticate_user!
    layout 'rails_profiler/application'
    
    helper_method :generate_sample_time_data
    
    private

    def authenticate_user!
      authenticate_or_request_with_http_basic do |username, password|
        username == RailsProfiler.config.dashboard_username &&
        password == RailsProfiler.config.dashboard_password
      end
    end
    
    # Helper method for generating sample time series data for charts when real data is unavailable
    def generate_sample_time_data(count = 6, value_type = 'count')
      current_time = Time.current
      
      # Create time points going backwards from current time
      data = []
      count.times do |i|
        time_ago = (count - i) * 10.minutes
        point_time = current_time - time_ago
        
        if value_type == 'count'
          value = rand(10..50)  # Random request count
        elsif value_type == 'avg_duration'
          value = rand(100..300)  # Random duration in ms
        else
          value = rand(1..100)  # Generic random value
        end
        
        data << {
          timestamp: point_time,
          count: value_type == 'count' ? value : rand(5..20),
          avg_duration: value_type == 'avg_duration' ? value : rand(50..250)
        }
      end
      
      data
    end
  end
end