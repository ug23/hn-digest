Rails.application.routes.draw do
  # ヘルスチェック。Rails 8 の既定で、プロセスが起動していれば 200 を返す
  get "up" => "rails/health#show", as: :rails_health_check

  root "digests#show"
  get "digests/:date", to: "digests#show", as: :digest, constraints: { date: /next|\d{4}-\d{2}-\d{2}/ }
  # feedback と translation は1記事に1件なので単数リソース。POST /stories/:story_id/feedback になる
  resources :stories, only: :show do
    resource :feedback, only: :create
    resource :translation, only: :create
  end
  resource :labeling, only: :show
  resource :profile, only: [ :edit, :update ]
end
