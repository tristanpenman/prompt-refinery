Rails.application.routes.draw do
  root "home#index"
  get "models" => "models#index", as: :models

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
  resources :trials, only: %i[index show create] do
    get :compare, on: :member, to: "trial_comparisons#show"
  end

  namespace :settings do
    resources :backends, only: %i[index create] do
      post :test_connection, on: :member
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
