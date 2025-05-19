module RailsProfiler
  class Profile < ActiveRecord::Base
    self.table_name = 'rails_profiler_profiles'
    
    validates :request_id, presence: true, uniqueness: true
  end
end