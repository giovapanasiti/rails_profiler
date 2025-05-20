RailsProfiler::Engine.routes.draw do
  root 'dashboard#index'
  get 'profiles', to: 'dashboard#profiles'
  get 'slowest_queries', to: 'dashboard#slowest_queries'
  get 'endpoints', to: 'dashboard#endpoints'
  get 'trends', to: 'dashboard#trends'
  get 'profiles/:id', to: 'dashboard#show', as: 'profile'
  
  # Add missing routes for the navigation
  get 'hotspots', to: 'dashboard#hotspots'
  get 'flame_graph', to: 'dashboard#flame_graph'
  get 'call_graph', to: 'dashboard#call_graph'
  
  # Diagnostic route for debugging
  get '/debug_profile', to: 'dashboard#debug_profile', as: :debug_profile
end