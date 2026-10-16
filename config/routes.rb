Rails.application.routes.draw do
  root "home#index"

  get "login" => "sessions#new", as: :login
  post "login" => "sessions#create"
  delete "logout" => "sessions#destroy", as: :logout

  get "up" => "rails/health#show", as: :rails_health_check
end
