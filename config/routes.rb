Rails.application.routes.draw do
  root "home#index"

  get "login" => "sessions#new", as: :login
  post "login" => "sessions#create"
  delete "logout" => "sessions#destroy", as: :logout

  get "prompt" => "prompts#show", as: :prompt
  post "prompt" => "prompts#create"
  get "evaluate" => "evaluations#show", as: :evaluate
  post "evaluate" => "evaluations#create"

  resources :collections, only: %i[index show create update destroy] do
    get :revisions, on: :member, to: "collection_revisions#index"
    patch :unarchive, on: :member
    resources :prompts, only: %i[create update destroy], controller: "collection_prompts"
  end
  resources :test_suites, only: %i[index show create update destroy] do
    patch :unarchive, on: :member
    resources :test_cases, only: %i[create update destroy]
  end
  resources :trials, only: %i[index show create] do
    get :compare, on: :member, to: "trial_comparisons#show"
  end

  get "settings" => "settings#index", as: :settings
  namespace :settings do
    resources :models, only: %i[index edit update]
    resources :backends, only: %i[index create edit update destroy] do
      post :test_connection, on: :member
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
