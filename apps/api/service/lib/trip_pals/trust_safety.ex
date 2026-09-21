defmodule TripPals.TrustSafety do
  @moduledoc """
  Server-owned safety policy for reports, blocks, restrictions, appeals, and
  staff actions. Reporter identity is deliberately absent from member-facing
  projections and subjects only receive their own restriction notices.
  """

  import Ecto.Query

  alias TripPals.Accounts.User
  alias TripPals.Platform
  alias TripPals.Repo
  alias TripPals.Safety.AccountRestriction
  alias TripPals.Safety.Appeal
  alias TripPals.Safety.AuditEntry
  alias TripPals.Safety.Block
  alias TripPals.Safety.ModerationCase
  alias TripPals.Safety.ModerationCaseEvent
  alias TripPals.Safety.Report
  alias TripPals.Safety.StaffRoleAssignment

  @staff_roles ~w(moderator administrator)
  @restriction_kinds ~w(join_freeze chat_freeze activity_review account_suspension)

  def submit_report(reporter_id, attributes) do
    Repo.transaction(fn ->
      report = %Report{reporter_id: reporter_id}

      with {:ok, report} <- Repo.insert(Report.changeset(report, report_attributes(attributes))),
           {:ok, moderation_case} <- create_case(report),
           {:ok, _event} <-
             append_case_event(
               moderation_case.id,
               reporter_id,
               "report_submitted",
               "report submitted",
               %{}
             ),
           :ok <- enqueue_report(report, moderation_case) do
        %{report_id: report.id, case_id: moderation_case.id, status: "submitted"}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def block(blocker_id, blocked_id, attributes \\ %{}) do
    Repo.transaction(fn ->
      with :ok <- blockable?(blocker_id, blocked_id),
           {:ok, block} <- upsert_block(blocker_id, blocked_id, attributes),
           {:ok, _audit} <-
             audit(blocker_id, blocked_id, nil, "member_blocked", "block", "member block"),
           :ok <- enqueue_block_effect(block) do
        block_view(block)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def unblock(blocker_id, blocked_id) do
    Repo.transaction(fn ->
      case Repo.get_by(Block, blocker_id: blocker_id, blocked_id: blocked_id) do
        nil ->
          %{blocked_id: blocked_id, status: "not_blocked"}

        block ->
          with {:ok, _block} <- Repo.delete(block),
               {:ok, _audit} <-
                 audit(blocker_id, blocked_id, nil, "member_unblocked", "block", "member unblock"),
               :ok <-
                 enqueue("safety", "safety.block_removed", "account", blocked_id, %{
                   blocker_id: blocker_id
                 }) do
            %{blocked_id: blocked_id, status: "unblocked"}
          else
            {:error, reason} -> Repo.rollback(reason)
          end
      end
    end)
  end

  def blocked?(first_user_id, second_user_id) do
    Repo.exists?(
      from(block in Block,
        where:
          (block.blocker_id == ^first_user_id and block.blocked_id == ^second_user_id) or
            (block.blocker_id == ^second_user_id and block.blocked_id == ^first_user_id)
      )
    )
  end

  def block_conflict?(user_id, other_user_ids) when is_list(other_user_ids) do
    ids = Enum.uniq(Enum.reject(other_user_ids, &is_nil/1))

    ids != [] and
      Repo.exists?(
        from(block in Block,
          where:
            (block.blocker_id == ^user_id and block.blocked_id in ^ids) or
              (block.blocked_id == ^user_id and block.blocker_id in ^ids)
        )
      )
  end

  def restrictions_for(user_id, now \\ DateTime.utc_now()) do
    from(restriction in AccountRestriction,
      where:
        restriction.user_id == ^user_id and restriction.status in ["active", "under_review"] and
          restriction.effective_at <= ^now and
          (is_nil(restriction.expires_at) or restriction.expires_at > ^now),
      order_by: [desc: restriction.effective_at]
    )
    |> Repo.all()
  end

  def restriction_active?(user_id, kind, now \\ DateTime.utc_now()) do
    Enum.any?(restrictions_for(user_id, now), &(&1.kind == kind))
  end

  def my_restrictions(user_id) do
    restrictions_for(user_id)
    |> Enum.map(&restriction_notice/1)
  end

  def submit_appeal(user_id, restriction_id, attributes) do
    Repo.transaction(fn ->
      with %AccountRestriction{} = restriction <-
             Repo.get_by(AccountRestriction, id: restriction_id, user_id: user_id),
           true <- restriction.status in ["active", "under_review"],
           {:ok, appeal} <-
             %Appeal{restriction_id: restriction.id, appellant_id: user_id}
             |> Appeal.changeset(%{statement: attributes["statement"] || attributes[:statement]})
             |> Repo.insert(),
           {:ok, _event} <-
             append_case_event(
               restriction.case_id,
               user_id,
               "appeal_submitted",
               "appeal submitted",
               %{}
             ),
           :ok <- enqueue("safety", "safety.appeal_submitted", "restriction", restriction.id, %{}) do
        appeal_view(appeal)
      else
        nil -> Repo.rollback(:not_found)
        false -> Repo.rollback(:appeal_not_available)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def grant_staff_role(actor_id, user_id, role, options \\ %{}) do
    Repo.transaction(fn ->
      with :ok <- administrator?(actor_id),
           true <- role in @staff_roles,
           {:ok, assignment} <-
             %StaffRoleAssignment{user_id: user_id, granted_by_id: actor_id}
             |> StaffRoleAssignment.changeset(%{
               role: role,
               scope_type: Map.get(options, :scope_type, "platform"),
               scope_id: Map.get(options, :scope_id)
             })
             |> Repo.insert(),
           {:ok, _audit} <-
             audit(actor_id, user_id, nil, "staff_role_granted", "staff", "staff role granted") do
        assignment
      else
        false -> Repo.rollback(:forbidden)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def staff_roles(user_id) do
    from(assignment in StaffRoleAssignment,
      where: assignment.user_id == ^user_id and is_nil(assignment.revoked_at),
      select: assignment.role
    )
    |> Repo.all()
    |> Enum.uniq()
  end

  def staff_case_queue(staff_id, params \\ %{}) do
    with :ok <- moderator?(staff_id) do
      limit = page_limit(params["limit"] || params[:limit])

      from(moderation_case in ModerationCase,
        join: report in Report,
        on: report.id == moderation_case.report_id,
        where: moderation_case.status in ["open", "investigating"],
        order_by: [asc: moderation_case.inserted_at],
        limit: ^limit,
        select: {moderation_case, report}
      )
      |> Repo.all()
      |> Enum.map(fn {moderation_case, report} -> staff_case_view(moderation_case, report) end)
      |> then(&{:ok, &1})
    end
  end

  def assign_case(staff_id, case_id, reason) do
    Repo.transaction(fn ->
      with :ok <- moderator?(staff_id),
           true <- meaningful_reason?(reason),
           %ModerationCase{} = moderation_case <- Repo.get(ModerationCase, case_id),
           {:ok, moderation_case} <-
             moderation_case
             |> ModerationCase.changeset(%{assigned_staff_id: staff_id, status: "investigating"})
             |> Repo.update(),
           {:ok, _event} <- append_case_event(case_id, staff_id, "case_assigned", reason, %{}),
           {:ok, _audit} <- audit(staff_id, nil, case_id, "case_assigned", "moderation", reason) do
        staff_case_view(moderation_case, nil)
      else
        false -> Repo.rollback(:reason_required)
        nil -> Repo.rollback(:not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def impose_restriction(staff_id, subject_id, attributes) do
    Repo.transaction(fn ->
      reason = value(attributes, "reason")
      kind = value(attributes, "kind")
      notice = value(attributes, "notice")
      case_id = value(attributes, "case_id")

      with :ok <- moderator?(staff_id),
           true <- kind in @restriction_kinds,
           true <- meaningful_reason?(reason),
           true <- meaningful_reason?(notice),
           %User{} <- Repo.get(User, subject_id),
           :ok <- case_belongs_to_subject?(case_id, subject_id),
           {:ok, restriction} <- insert_restriction(staff_id, subject_id, attributes),
           {:ok, _event} <-
             append_case_event(case_id, staff_id, "restriction_imposed", reason, %{kind: kind}),
           {:ok, _audit} <-
             audit(staff_id, subject_id, case_id, "restriction_imposed", "moderation", reason),
           :ok <- reconcile_restriction(restriction) do
        restriction_notice(restriction)
      else
        false -> Repo.rollback(:reason_required)
        nil -> Repo.rollback(:not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def review_appeal(staff_id, appeal_id, decision, reason)
      when decision in ["upheld", "overturned"] do
    Repo.transaction(fn ->
      with :ok <- moderator?(staff_id),
           true <- meaningful_reason?(reason),
           %Appeal{} = appeal <- Repo.get(Appeal, appeal_id),
           true <- appeal.status in ["submitted", "in_review"],
           {:ok, appeal} <-
             appeal
             |> Appeal.changeset(%{
               status: decision,
               decision_reason: reason,
               reviewed_at: DateTime.utc_now()
             })
             |> Ecto.Changeset.put_change(:reviewed_by_id, staff_id)
             |> Repo.update(),
           :ok <- maybe_lift_restriction(appeal, decision),
           {:ok, _audit} <-
             audit(staff_id, appeal.appellant_id, nil, "appeal_#{decision}", "moderation", reason),
           :ok <- enqueue("safety", "safety.appeal_#{decision}", "appeal", appeal.id, %{}) do
        appeal_view(appeal)
      else
        false -> Repo.rollback(:reason_required)
        nil -> Repo.rollback(:not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp report_attributes(attributes) do
    %{
      target_type: value(attributes, "target_type"),
      target_id: value(attributes, "target_id"),
      reason_code: value(attributes, "reason_code"),
      evidence_reference: value(attributes, "evidence_reference"),
      context: Map.take(value(attributes, "context") || %{}, ["surface", "occurred_at", "note"]),
      urgency:
        if(value(attributes, "reason_code") == "immediate_safety_concern",
          do: "urgent",
          else: "standard"
        )
    }
  end

  defp create_case(report) do
    %ModerationCase{report_id: report.id}
    |> ModerationCase.changeset(%{target_type: report.target_type, target_id: report.target_id})
    |> Repo.insert()
  end

  defp upsert_block(blocker_id, blocked_id, attributes) do
    case Repo.get_by(Block, blocker_id: blocker_id, blocked_id: blocked_id) do
      %Block{} = block ->
        {:ok, block}

      nil ->
        %Block{blocker_id: blocker_id, blocked_id: blocked_id}
        |> Block.changeset(%{reason_code: value(attributes, "reason_code"), source: "member"})
        |> Repo.insert()
    end
  end

  defp blockable?(blocker_id, blocked_id) do
    cond do
      blocker_id == blocked_id -> {:error, :cannot_block_self}
      is_nil(Repo.get(User, blocked_id)) -> {:error, :not_found}
      true -> :ok
    end
  end

  defp insert_restriction(staff_id, subject_id, attributes) do
    now = DateTime.utc_now()

    %AccountRestriction{
      user_id: subject_id,
      imposed_by_id: staff_id,
      case_id: value(attributes, "case_id")
    }
    |> AccountRestriction.changeset(%{
      kind: value(attributes, "kind"),
      scope: value(attributes, "scope") || "account",
      reason: value(attributes, "reason"),
      notice: value(attributes, "notice"),
      effective_at: now,
      expires_at: value(attributes, "expires_at"),
      review_at: value(attributes, "review_at")
    })
    |> Repo.insert()
  end

  defp reconcile_restriction(restriction) do
    event_type =
      case restriction.kind do
        "chat_freeze" -> "safety.chat_freeze"
        "activity_review" -> "safety.activity_review"
        "join_freeze" -> "safety.join_freeze"
        "account_suspension" -> "safety.account_suspension"
      end

    enqueue("safety", event_type, "account", restriction.user_id, %{
      restriction_id: restriction.id,
      kind: restriction.kind,
      notice: restriction.notice
    })
  end

  defp enqueue_report(report, moderation_case) do
    event_type =
      if report.urgency == "urgent", do: "safety.urgent_report", else: "safety.report_submitted"

    enqueue("safety", event_type, "moderation_case", moderation_case.id, %{report_id: report.id})
  end

  defp enqueue_block_effect(block),
    do:
      enqueue("safety", "safety.block_added", "account", block.blocked_id, %{
        blocker_id: block.blocker_id
      })

  defp enqueue(topic, event_type, aggregate_type, aggregate_id, payload) do
    case Platform.enqueue_outbox_event(%{
           topic: topic,
           event_type: event_type,
           aggregate_type: aggregate_type,
           aggregate_id: aggregate_id,
           payload: payload,
           available_at: DateTime.utc_now()
         }) do
      {:ok, _event} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp append_case_event(nil, _actor_id, _event_type, _reason, _details), do: {:ok, :no_case}

  defp append_case_event(case_id, actor_id, event_type, reason, details) do
    %ModerationCaseEvent{case_id: case_id, actor_id: actor_id}
    |> ModerationCaseEvent.changeset(%{event_type: event_type, reason: reason, details: details})
    |> Repo.insert()
  end

  defp audit(actor_id, subject_id, case_id, action, scope, reason) do
    %AuditEntry{actor_id: actor_id, subject_id: subject_id, case_id: case_id}
    |> AuditEntry.changeset(%{action: action, scope: scope, reason: reason})
    |> Repo.insert()
  end

  defp case_belongs_to_subject?(nil, _subject_id), do: :ok

  defp case_belongs_to_subject?(case_id, subject_id) do
    case Repo.get(ModerationCase, case_id) do
      %ModerationCase{target_type: "account", target_id: ^subject_id} -> :ok
      %ModerationCase{} -> {:error, :case_target_mismatch}
      nil -> {:error, :not_found}
    end
  end

  defp maybe_lift_restriction(appeal, "overturned") do
    restriction = Repo.get!(AccountRestriction, appeal.restriction_id)

    restriction
    |> AccountRestriction.changeset(%{status: "lifted", lifted_at: DateTime.utc_now()})
    |> Repo.update()
    |> then(fn
      {:ok, _} -> :ok
      error -> error
    end)
  end

  defp maybe_lift_restriction(_appeal, _decision), do: :ok

  defp moderator?(user_id),
    do:
      if(Enum.any?(staff_roles(user_id), &(&1 in @staff_roles)),
        do: :ok,
        else: {:error, :forbidden}
      )

  defp administrator?(user_id),
    do: if("administrator" in staff_roles(user_id), do: :ok, else: {:error, :forbidden})

  defp meaningful_reason?(reason),
    do: is_binary(reason) and String.length(String.trim(reason)) >= 3

  defp page_limit(value) when is_integer(value) and value in 1..50, do: value

  defp page_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number in 1..50 -> number
      _ -> 20
    end
  end

  defp page_limit(_), do: 20

  defp value(attributes, key), do: Map.get(attributes, key) || Map.get(attributes, known_key(key))

  defp known_key("target_type"), do: :target_type
  defp known_key("target_id"), do: :target_id
  defp known_key("reason_code"), do: :reason_code
  defp known_key("evidence_reference"), do: :evidence_reference
  defp known_key("context"), do: :context
  defp known_key("statement"), do: :statement
  defp known_key("reason"), do: :reason
  defp known_key("kind"), do: :kind
  defp known_key("notice"), do: :notice
  defp known_key("case_id"), do: :case_id
  defp known_key("scope"), do: :scope
  defp known_key("expires_at"), do: :expires_at
  defp known_key("review_at"), do: :review_at

  defp block_view(block), do: %{blocked_id: block.blocked_id, status: "blocked"}

  defp restriction_notice(restriction),
    do: %{
      id: restriction.id,
      kind: restriction.kind,
      scope: restriction.scope,
      notice: restriction.notice,
      status: restriction.status,
      effective_at: restriction.effective_at,
      expires_at: restriction.expires_at,
      review_at: restriction.review_at,
      appeal_available: restriction.status in ["active", "under_review"]
    }

  defp appeal_view(appeal),
    do: %{
      id: appeal.id,
      restriction_id: appeal.restriction_id,
      status: appeal.status,
      statement: appeal.statement,
      decision_reason: appeal.decision_reason,
      reviewed_at: appeal.reviewed_at
    }

  defp staff_case_view(moderation_case, report),
    do: %{
      id: moderation_case.id,
      target_type: moderation_case.target_type,
      target_id: moderation_case.target_id,
      status: moderation_case.status,
      assigned_staff_id: moderation_case.assigned_staff_id,
      report:
        if(report,
          do: %{
            id: report.id,
            reason_code: report.reason_code,
            urgency: report.urgency,
            status: report.status
          },
          else: nil
        )
    }
end
