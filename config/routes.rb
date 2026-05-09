Rails.application.routes.draw do
  root 'dashboard#index'

  resources :transactions
  resources :invoices
  resources :expenses
  resources :accounts
end
