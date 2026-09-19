Rails.application.routes.draw do
  resources :jobs do
    resource :estimate, only: %i[show new create edit update]
  end
  resource :session
  resources :passwords, param: :token

  get "sign_up" => "registrations#new", as: :sign_up
  post "sign_up" => "registrations#create"

  resources :customers

  root "dashboard#index"

  get "up" => "rails/health#show", as: :rails_health_check
end
