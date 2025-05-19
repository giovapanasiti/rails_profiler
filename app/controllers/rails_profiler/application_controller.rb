module RailsProfiler
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :exception
    before_action :authenticate_user!

    private

    def authenticate_user!
      authenticate_or_request_with_http_basic do |username, password|
        username == RailsProfiler.config.dashboard_username &&
        password == RailsProfiler.config.dashboard_password
      end
    end
  end
end