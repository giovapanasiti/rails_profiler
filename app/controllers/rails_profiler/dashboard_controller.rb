module RailsProfiler
  class DashboardController < ApplicationController
    def index
      @stats = Storage.get_summary_stats
      @profiles = @stats[:latest_profiles] || []
    end

    def show
      @profile = Storage.get_profile(params[:id])
      redirect_to rails_profiler.dashboard_index_path unless @profile
    end

    def profiles
      page = (params[:page] || 1).to_i
      per_page = 50
      offset = (page - 1) * per_page
      
      @profiles = Storage.get_profiles(limit: per_page, offset: offset)
      @current_page = page
    end
  end
end