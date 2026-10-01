Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  resource :site_gate, path: "unlock", only: [:new, :create]
  resource :session, only: [:new, :create, :destroy]
  resource :registration, path: "sign-up", only: [:new, :create]
  resource :user_account, path: "account", only: [:show, :update, :destroy]
  patch "account/password", to: "user_accounts#update_password", as: :user_account_password

  root 'dashboard#index'

  resource :amazon_connection, path: "amazon/connection", only: [:new, :destroy] do
    get :login
    get :callback
  end
  resources :amazon_syncs, path: "amazon/syncs", only: [:create]
  resources :amazon_import_batches, path: "amazon-imports", only: [:index, :new, :create, :show]
  resources :amazon_import_rows, path: "amazon-import-rows", only: [:update]
  resource :tax_packet, path: "tax-packet", only: [:show]
  resource :turbo_tax_export, path: "turbotax-export", only: [:show, :update] do
    get :download
  end
end
