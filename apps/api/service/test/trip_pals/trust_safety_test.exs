defmodule TripPals.TrustSafetyTest do
  use TripPals.DataCase, async: true

  alias TripPals.Accounts
  alias TripPals.Repo
  alias TripPals.Safety.AuditEntry
  alias TripPals.Safety.ModerationCase
  alias TripPals.Safety.Report
  alias TripPals.Safety.StaffRoleAssignment
  alias TripPals.TrustSafety

  setup do
    {:ok, reporter} = Accounts.create_user()
    {:ok, subject} = Accounts.create_user()
    {:ok, moderator} = Accounts.create_user()

    Repo.insert!(
      StaffRoleAssignment.changeset(%StaffRoleAssignment{user_id: moderator.id}, %{
        role: "moderator",
        scope_type: "platform"
      })
    )

    %{reporter: reporter, subject: subject, moderator: moderator}
  end

  test "a report creates an urgent case without exposing its reporter in staff queue projections",
       %{
         reporter: reporter,
         subject: subject,
         moderator: moderator
       } do
    assert {:ok, %{report_id: report_id, case_id: case_id, status: "submitted"}} =
             TrustSafety.submit_report(reporter.id, %{
               "target_type" => "account",
               "target_id" => subject.id,
               "reason_code" => "immediate_safety_concern",
               "context" => %{"surface" => "activity_detail", "ignored" => "not retained"}
             })

    assert %Report{reporter_id: reporter_id, urgency: "urgent"} = Repo.get!(Report, report_id)
    assert reporter_id == reporter.id

    assert %ModerationCase{id: ^case_id, target_id: subject_id} =
             Repo.get!(ModerationCase, case_id)

    assert subject_id == subject.id

    assert {:ok, [queue_case]} = TrustSafety.staff_case_queue(moderator.id)
    refute Map.has_key?(queue_case, :reporter_id)
    refute Map.has_key?(queue_case.report, :reporter_id)
  end

  test "blocks are pair-unique, idempotent, and reject self-blocking", %{
    reporter: reporter,
    subject: subject
  } do
    assert {:ok, %{status: "blocked"}} = TrustSafety.block(reporter.id, subject.id)
    assert {:ok, %{status: "blocked"}} = TrustSafety.block(reporter.id, subject.id)
    assert TrustSafety.blocked?(reporter.id, subject.id)
    assert TrustSafety.block_conflict?(reporter.id, [subject.id])
    assert {:error, :cannot_block_self} = TrustSafety.block(reporter.id, reporter.id)
    assert {:ok, %{status: "unblocked"}} = TrustSafety.unblock(reporter.id, subject.id)
    refute TrustSafety.blocked?(reporter.id, subject.id)
  end

  test "staff actions require a role and a reason, issue member-safe notices, and allow an appeal",
       %{
         reporter: reporter,
         subject: subject,
         moderator: moderator
       } do
    assert {:ok, %{case_id: case_id}} =
             TrustSafety.submit_report(reporter.id, %{
               "target_type" => "account",
               "target_id" => subject.id,
               "reason_code" => "abuse"
             })

    assert {:error, :forbidden} =
             TrustSafety.impose_restriction(reporter.id, subject.id, %{
               "kind" => "join_freeze",
               "reason" => "Repeated abuse",
               "notice" => "Joining is temporarily unavailable",
               "case_id" => case_id
             })

    assert {:error, :reason_required} =
             TrustSafety.impose_restriction(moderator.id, subject.id, %{
               "kind" => "join_freeze",
               "reason" => "",
               "notice" => "Joining is temporarily unavailable",
               "case_id" => case_id
             })

    assert {:ok, %{id: restriction_id, kind: "join_freeze", appeal_available: true}} =
             TrustSafety.impose_restriction(moderator.id, subject.id, %{
               "kind" => "join_freeze",
               "reason" => "Repeated abuse",
               "notice" => "Joining is temporarily unavailable",
               "case_id" => case_id
             })

    assert [%{id: ^restriction_id, notice: "Joining is temporarily unavailable"}] =
             TrustSafety.my_restrictions(subject.id)

    assert {:ok, %{restriction_id: ^restriction_id, status: "submitted"}} =
             TrustSafety.submit_appeal(subject.id, restriction_id, %{
               "statement" => "Please review this."
             })
  end

  test "audit rows are immutable at the database boundary", %{
    reporter: reporter,
    subject: subject
  } do
    assert {:ok, _} = TrustSafety.block(reporter.id, subject.id)
    audit = Repo.one!(AuditEntry)

    assert_raise Postgrex.Error, fn ->
      audit
      |> Ecto.Changeset.change(reason: "changed")
      |> Repo.update!()
    end
  end
end
