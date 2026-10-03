defmodule Averziano.Training do
  @moduledoc """
  Training domain: a coach's program for a client, its scheduled sessions
  ("giornate"), the exercises prescribed in each session and the sets the
  client logs while training.
  """

  use Ash.Domain, otp_app: :averziano

  resources do
    resource Averziano.Training.Template do
      define :create_template, action: :create
      define :update_template, action: :update
      define :destroy_template, action: :destroy
      define :list_templates, action: :library
      define :get_template, action: :read, get_by: [:id]
    end

    resource Averziano.Training.Program do
      define :create_program, action: :create
      define :update_program_plan, action: :update_plan
      define :publish_program, action: :publish
      define :current_program, action: :current, not_found_error?: false
      define :list_coached_programs, action: :coached

      define :latest_client_program,
        action: :latest_for_client,
        args: [:client_id],
        not_found_error?: false

      define :get_program, action: :read, get_by: [:id]
    end

    resource Averziano.Training.Session do
      define :create_session, action: :create
      define :get_session, action: :read, get_by: [:id]
      define :complete_session, action: :complete
      define :review_session, action: :review
      define :list_completed_sessions, action: :completed_for_coach
    end

    resource Averziano.Training.Exercise do
      define :create_exercise, action: :create
      define :get_exercise, action: :read, get_by: [:id]
      define :update_exercise_target, action: :update_target
      define :retarget_exercise, action: :retarget, args: [:exercise_id, :scope, :target]

      define :exercise_replicas,
        action: :replicas,
        args: [:program_id, :day_label, :name, :after]

      define :previous_performance,
        action: :previous,
        args: [:program_id, :name, :before],
        get?: true,
        not_found_error?: false
    end

    resource Averziano.Training.ClientNote do
      define :create_client_note, action: :create
      define :update_client_note, action: :update
      define :destroy_client_note, action: :destroy
      define :list_client_notes, action: :for_client, args: [:client_id]
    end

    resource Averziano.Training.SetLog do
      define :log_set, action: :log
    end
  end
end
