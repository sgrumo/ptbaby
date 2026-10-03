defmodule Averziano.Training.PlanDay do
  @moduledoc """
  A training day of a plan ("Giorno A · Upper body"), repeated every week on
  `weekdays` (ISO: 1 = Monday … 7 = Sunday). Its letter is its position in
  the plan.
  """

  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :weekdays, {:array, :integer} do
      allow_nil? false
      public? true
      default []
      constraints items: [min: 1, max: 7]
    end

    attribute :exercises, {:array, Averziano.Training.PlanExercise} do
      allow_nil? false
      public? true
      default []
    end
  end
end
