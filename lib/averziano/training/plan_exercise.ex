defmodule Averziano.Training.PlanExercise do
  @moduledoc """
  An exercise of a plan day (in a template or a program draft). Publishing a
  program copies it into a dated `Averziano.Training.Exercise`; see that
  module for the meaning of `kind` and the targets.
  """

  use Ash.Resource, data_layer: :embedded

  validations do
    validate present(:target_reps), where: [attribute_equals(:kind, :reps)]
    validate present(:target_seconds), where: [attribute_equals(:kind, :time)]
    validate present(:sequence), where: [attribute_equals(:kind, :sequence)]
  end

  attributes do
    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :kind, :atom do
      allow_nil? false
      public? true
      default :reps
      constraints one_of: [:reps, :max, :time, :sequence]
    end

    attribute :sets_count, :integer do
      allow_nil? false
      public? true
      default 3
      constraints min: 1
    end

    attribute :target_reps, :integer do
      public? true
      constraints min: 1
    end

    attribute :target_load_kg, :decimal do
      public? true
      constraints min: 0
    end

    attribute :target_seconds, :integer do
      public? true
      constraints min: 1
    end

    attribute :sequence, {:array, :integer} do
      public? true
      constraints min_length: 1, items: [min: 1]
    end

    attribute :sequence_rest_seconds, :integer do
      public? true
      constraints min: 0
    end

    attribute :rest_seconds, :integer do
      allow_nil? false
      public? true
      default 90
      constraints min: 0
    end

    attribute :notes, :string do
      public? true
    end

    attribute :videos, {:array, Averziano.Training.Video} do
      allow_nil? false
      public? true
      default []
    end
  end
end
