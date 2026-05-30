Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root 'dashboard#index'

  resources :amazon_import_batches, path: "amazon-imports", only: [:index, :new, :create, :show]
  resources :amazon_import_rows, path: "amazon-import-rows", only: [:update]
  resource :tax_packet, path: "tax-packet", only: [:show]
  resource :turbo_tax_export, path: "turbotax-export", only: [:show, :update] do
    get :download
  end
end
