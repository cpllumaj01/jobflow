Rails.application.routes.draw do
  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      resources :jobs, only: %i[index show]
    end
  end

  resources :jobs do
    resources :attachments, only: %i[show create destroy], controller: "job_attachments"
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
  resource :two_factor_challenge, only: %i[new create destroy]
  resource :account, only: :show
  resource :account_security, controller: "account_security", only: :show do
    post :setup
    patch :enable
    delete :cancel_setup
    post :recovery_codes
    delete :two_factor
  end
  resources :passwords, param: :token

  get "sign_up" => "registrations#new", as: :sign_up
  post "sign_up" => "registrations#create"

  resources :customers

  root "dashboard#index"

  get "up" => "rails/health#show", as: :rails_health_check
end
