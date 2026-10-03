defmodule Averziano.Training.Video do
  @moduledoc "A reference video (usually YouTube) attached to an exercise."

  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :url, :string do
      allow_nil? false
      public? true
    end
  end
end
