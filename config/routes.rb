RailsProfiler::Engine.routes.draw do
  root 'dashboard#index'
  get 'profiles', to: 'dashboard#profiles'
  get 'profiles/:id', to: 'dashboard#show', as: 'profile'
end