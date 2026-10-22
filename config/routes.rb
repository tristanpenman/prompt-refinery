Rails.application.routes.draw do
  root "home#index"

  get "login" => "sessions#new", as: :login
  post "login" => "sessions#create"
  delete "logout" => "sessions#destroy", as: :logout

  get "playground" => "playgrounds#show", as: :playground
  post "playground" => "playgrounds#create"
  get "evaluate" => "evaluations#show", as: :evaluate
  post "evaluate" => "evaluations#create"

  resources :prompts, only: %i[index show create update destroy] do
    get :revisions, on: :member, to: "prompt_revisions#index"
    patch :unarchive, on: :member
  end
  resources :test_suite_imports, only: %i[create show update destroy]
  resources :test_suites, only: %i[index show create update destroy] do
    get :revisions, on: :member, to: "test_suite_revisions#index"
    get :csv, on: :member, to: "test_suite_csvs#show"
    patch :unarchive, on: :member
    resources :test_cases, only: %i[create update destroy]
  end
  resources :refinements, only: %i[index show create]
  resources :trials, only: %i[index show create] do
    get :compare, on: :member, to: "trial_comparisons#show"
  end

  get "settings" => "settings#index", as: :settings
  namespace :settings do
    resources :models, only: %i[index edit update] do
      post :refresh, on: :collection
    end
    resources :backends, only: %i[index create edit update destroy] do
      post :test_connection, on: :member
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
