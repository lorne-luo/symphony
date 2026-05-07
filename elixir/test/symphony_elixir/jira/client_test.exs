defmodule SymphonyElixir.Jira.ClientTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Jira.Client
  alias SymphonyElixir.Linear.Issue

  @sample_issue %{
    "id" => "10001",
    "key" => "SYM-1",
    "fields" => %{
      "summary" => "Hello world",
      "description" => nil,
      "priority" => %{"id" => "3"},
      "status" => %{"name" => "To Do"},
      "assignee" => %{"accountId" => "user-1"},
      "labels" => ["Bug", "backend"],
      "issuelinks" => [],
      "created" => "2026-01-01T00:00:00.000+0000",
      "updated" => "2026-01-02T00:00:00.000+0000"
    }
  }

  setup do
    Application.put_env(:symphony_elixir, :test_config, %{
      tracker: %{
        kind: "jira",
        endpoint: "https://example.atlassian.net",
        api_key: "test-token",
        email: "test@example.com",
        project_key: "SYM",
        assignee: nil,
        active_states: ["To Do", "In Progress"],
        terminal_states: ["Done"]
      }
    })

    on_exit(fn -> Application.delete_env(:symphony_elixir, :test_config) end)
    :ok
  end

  describe "normalize_issue_for_test/1" do
    test "maps all standard fields to an Issue struct" do
      issue = Client.normalize_issue_for_test(@sample_issue)

      assert %Issue{} = issue
      assert issue.id == "SYM-1"
      assert issue.identifier == "SYM-1"
      assert issue.title == "Hello world"
      assert issue.description == nil
      assert issue.priority == 3
      assert issue.state == "To Do"
      assert issue.assignee_id == "user-1"
      assert issue.labels == ["bug", "backend"]
      assert issue.blocked_by == []
      assert issue.assigned_to_worker == true
      assert %DateTime{} = issue.created_at
      assert %DateTime{} = issue.updated_at
    end

    test "generates branch_name from key and summary" do
      issue = Client.normalize_issue_for_test(@sample_issue)
      assert issue.branch_name == "sym-1-hello-world"
    end

    test "branch_name slugifies non-alphanumeric chars" do
      issue =
        Client.normalize_issue_for_test(
          put_in(@sample_issue, ["fields", "summary"], "Fix: user's login & auth!")
        )

      assert issue.branch_name == "sym-1-fix-user-s-login-auth"
    end

    test "branch_name is truncated to 40 chars in slug portion" do
      long_summary = String.duplicate("a", 60)

      issue =
        Client.normalize_issue_for_test(
          put_in(@sample_issue, ["fields", "summary"], long_summary)
        )

      slug = issue.branch_name |> String.replace_prefix("sym-1-", "")
      assert String.length(slug) <= 40
    end

    test "handles nil summary gracefully" do
      issue =
        Client.normalize_issue_for_test(
          put_in(@sample_issue, ["fields", "summary"], nil)
        )

      assert issue.branch_name == "sym-1"
    end

    test "handles string description" do
      issue =
        Client.normalize_issue_for_test(
          put_in(@sample_issue, ["fields", "description"], "plain text")
        )

      assert issue.description == "plain text"
    end

    test "converts ADF map description to JSON string" do
      adf = %{"type" => "doc", "content" => []}

      issue =
        Client.normalize_issue_for_test(
          put_in(@sample_issue, ["fields", "description"], adf)
        )

      assert is_binary(issue.description)
      assert issue.description =~ "doc"
    end

    test "extracts blocked_by from issuelinks with 'is blocked by' inward type" do
      issuelinks = [
        %{
          "type" => %{"inward" => "is blocked by", "outward" => "blocks"},
          "inwardIssue" => %{
            "key" => "SYM-0",
            "fields" => %{"status" => %{"name" => "In Progress"}}
          }
        }
      ]

      issue =
        Client.normalize_issue_for_test(
          put_in(@sample_issue, ["fields", "issuelinks"], issuelinks)
        )

      assert [%{id: "SYM-0", identifier: "SYM-0", state: "In Progress"}] = issue.blocked_by
    end

    test "ignores outward issue links (non-blocking)" do
      issuelinks = [
        %{
          "type" => %{"inward" => "is blocked by", "outward" => "blocks"},
          "outwardIssue" => %{"key" => "SYM-99"}
        }
      ]

      issue =
        Client.normalize_issue_for_test(
          put_in(@sample_issue, ["fields", "issuelinks"], issuelinks)
        )

      assert issue.blocked_by == []
    end

    test "parses priority as integer" do
      issue = Client.normalize_issue_for_test(@sample_issue)
      assert issue.priority == 3
    end

    test "handles nil priority" do
      issue =
        Client.normalize_issue_for_test(
          put_in(@sample_issue, ["fields", "priority"], nil)
        )

      assert issue.priority == nil
    end

    test "labels are lowercased" do
      issue = Client.normalize_issue_for_test(@sample_issue)
      assert "bug" in issue.labels
      assert "backend" in issue.labels
    end

    test "returns nil for issue with no key" do
      issue = Map.delete(@sample_issue, "key")
      result = Client.normalize_issue_for_test(issue)
      assert result.id == nil
      assert result.identifier == nil
    end
  end

  describe "fetch_candidate_issues/0" do
    test "returns error when api_key is nil" do
      Application.put_env(:symphony_elixir, :test_config, %{
        tracker: %{
          kind: "jira",
          api_key: nil,
          email: "a@b.com",
          project_key: "SYM",
          active_states: ["To Do"],
          terminal_states: ["Done"],
          assignee: nil,
          endpoint: "https://example.atlassian.net"
        }
      })

      assert {:error, :missing_jira_api_token} = Client.fetch_candidate_issues()
    end

    test "returns error when email is nil" do
      Application.put_env(:symphony_elixir, :test_config, %{
        tracker: %{
          kind: "jira",
          api_key: "tok",
          email: nil,
          project_key: "SYM",
          active_states: ["To Do"],
          terminal_states: ["Done"],
          assignee: nil,
          endpoint: "https://example.atlassian.net"
        }
      })

      assert {:error, :missing_jira_email} = Client.fetch_candidate_issues()
    end

    test "returns error when project_key is nil" do
      Application.put_env(:symphony_elixir, :test_config, %{
        tracker: %{
          kind: "jira",
          api_key: "tok",
          email: "a@b.com",
          project_key: nil,
          active_states: ["To Do"],
          terminal_states: ["Done"],
          assignee: nil,
          endpoint: "https://example.atlassian.net"
        }
      })

      assert {:error, :missing_jira_project_key} = Client.fetch_candidate_issues()
    end

    test "returns empty list when active_states is empty" do
      Application.put_env(:symphony_elixir, :test_config, %{
        tracker: %{
          kind: "jira",
          api_key: "tok",
          email: "a@b.com",
          project_key: "SYM",
          active_states: [],
          terminal_states: ["Done"],
          assignee: nil,
          endpoint: "https://example.atlassian.net"
        }
      })

      assert {:ok, []} = Client.fetch_candidate_issues()
    end
  end

  describe "fetch_issues_by_states/1" do
    test "returns empty list for empty state list" do
      assert {:ok, []} = Client.fetch_issues_by_states([])
    end
  end

  describe "fetch_issue_states_by_ids/1" do
    test "returns empty list for empty id list" do
      assert {:ok, []} = Client.fetch_issue_states_by_ids([])
    end
  end
end
