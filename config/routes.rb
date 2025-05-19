RailsProfiler::Engine.routes.draw do
  root 'dashboard#index'
  get 'profiles', to: 'dashboard#profiles'
  get 'slowest_queries', to: 'dashboard#slowest_queries'
  get 'profiles/:id', to: 'dashboard#show', as: 'profile'
end