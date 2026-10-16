Rails.application.routes.draw do
  root "home#index"

  get "login" => "sessions#new", as: :login
  post "login" => "sessions#create"
  delete "logout" => "sessions#destroy", as: :logout

  get "prompt" => "prompts#show", as: :prompt
  post "prompt" => "prompts#create"

  get "up" => "rails/health#show", as: :rails_health_check
end
