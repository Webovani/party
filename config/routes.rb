Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "party#index"

  # Nickname (self-set identity, no password)
  resource :session, only: %i[create destroy]

  # Multi-source search
  get "search", to: "search#index"

  # The shared live queue
  resources :queue_items, only: %i[create destroy] do
    member do
      post :move_to_front
    end
    collection do
      post :add_album
      post :add_folder
    end
  end

  # Skip-voting
  resources :skip_votes, only: :create

  # Playback controls -> player daemon (via NOTIFY)
  controller :player do
    post "player/play"   => :play
    post "player/pause"  => :pause
    post "player/skip"   => :skip
    post "player/volume" => :volume
    post "player/seek"   => :seek
  end

  # Browse the local library and play history
  get "library", to: "library#index"
  get "history", to: "history#index"
  get "history/export", to: "history#export", defaults: { format: "csv" }

  # Local library maintenance
  post "library/rescan", to: "library#rescan"
end
