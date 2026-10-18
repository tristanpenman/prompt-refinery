class SettingsController < ApplicationController
  def index
    @backends = Backend.order(system: :desc, name: :asc, id: :asc)
  end
end
