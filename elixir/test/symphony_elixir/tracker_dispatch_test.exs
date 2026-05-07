defmodule SymphonyElixir.TrackerDispatchTest do
  use ExUnit.Case, async: true

  test "Jira.Adapter is loaded and implements the Tracker behaviour" do
    assert Code.ensure_loaded?(SymphonyElixir.Jira.Adapter)

    callbacks = SymphonyElixir.Tracker.behaviour_info(:callbacks)

    for {fun, arity} <- callbacks do
      assert SymphonyElixir.Jira.Adapter.__info__(:functions)
             |> Keyword.get(fun) == arity,
             "Jira.Adapter is missing #{fun}/#{arity}"
    end
  end

  test "Jira.Adapter exports fetch_candidate_issues/0" do
    Code.ensure_loaded!(SymphonyElixir.Jira.Adapter)
    assert function_exported?(SymphonyElixir.Jira.Adapter, :fetch_candidate_issues, 0)
  end
end
