Rails.application.routes.draw do
  resources :jobs do
    resources :change_orders, only: %i[index show new create edit update] do
      member do
        patch :mark_pending
        patch :approve
        patch :reject
      end
    end
    resource :estimate, only: %i[show new create edit update] do
      patch :mark_sent
      patch :approve
      patch :reject
    end
  end
  resource :session
  resources :passwords, param: :token

  get "sign_up" => "registrations#new", as: :sign_up
  post "sign_up" => "registrations#create"

  resources :customers

  root "dashboard#index"

  get "up" => "rails/health#show", as: :rails_health_check
end
