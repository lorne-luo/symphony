defmodule SymphonyElixir.Jira.AdapterTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Jira.Adapter

  # ---------------------------------------------------------------------------
  # Stub client module — controlled via the process dictionary
  # ---------------------------------------------------------------------------
  defmodule StubClient do
    def fetch_candidate_issues, do: {:ok, []}
    def fetch_issues_by_states(_states), do: {:ok, []}
    def fetch_issue_states_by_ids(_ids), do: {:ok, []}

    def request(method, path, body \\ nil) do
      handler = Process.get(:stub_client_handler)

      if is_function(handler, 3) do
        handler.(method, path, body)
      else
        raise "StubClient: no handler set for #{inspect(method)} #{path}"
      end
    end
  end

  setup do
    Application.put_env(:symphony_elixir, :test_config, %{
      tracker: %{
        kind: "jira",
        endpoint: "http://localhost:4000",
        api_key: "tok",
        email: "a@b.com",
        project_key: "SYM",
        active_states: ["To Do"],
        terminal_states: ["Done"],
        assignee: nil
      }
    })

    Application.put_env(:symphony_elixir, :jira_client_module, StubClient)

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :test_config)
      Application.delete_env(:symphony_elixir, :jira_client_module)
    end)

    :ok
  end

  describe "create_comment/2" do
    test "returns :ok on successful POST" do
      Process.put(:stub_client_handler, fn :post, "/rest/api/3/issue/SYM-1/comment", _body ->
        {:ok, %{"id" => "10001", "body" => "hello"}}
      end)

      assert :ok = Adapter.create_comment("SYM-1", "hello")
    end

    test "returns error when client returns error" do
      Process.put(:stub_client_handler, fn :post, "/rest/api/3/issue/SYM-404/comment", _body ->
        {:error, {:jira_api_status, 404}}
      end)

      assert {:error, {:jira_api_status, 404}} = Adapter.create_comment("SYM-404", "hello")
    end
  end

  describe "update_issue_state/2" do
    test "returns :ok when transition found and POST succeeds" do
      Process.put(:stub_client_handler, fn method, path, _body ->
        case {method, path} do
          {:get, "/rest/api/3/issue/SYM-1/transitions"} ->
            {:ok,
             %{
               "transitions" => [
                 %{"id" => "11", "to" => %{"name" => "In Progress"}},
                 %{"id" => "21", "to" => %{"name" => "Done"}}
               ]
             }}

          {:post, "/rest/api/3/issue/SYM-1/transitions"} ->
            {:ok, %{}}
        end
      end)

      assert :ok = Adapter.update_issue_state("SYM-1", "Done")
    end

    test "is case-insensitive when matching transition name" do
      Process.put(:stub_client_handler, fn method, path, _body ->
        case {method, path} do
          {:get, "/rest/api/3/issue/SYM-2/transitions"} ->
            {:ok,
             %{
               "transitions" => [
                 %{"id" => "31", "to" => %{"name" => "In Review"}}
               ]
             }}

          {:post, "/rest/api/3/issue/SYM-2/transitions"} ->
            {:ok, %{}}
        end
      end)

      assert :ok = Adapter.update_issue_state("SYM-2", "in review")
    end

    test "returns error when transition not found" do
      Process.put(:stub_client_handler, fn :get, "/rest/api/3/issue/SYM-3/transitions", _body ->
        {:ok,
         %{
           "transitions" => [
             %{"id" => "11", "to" => %{"name" => "In Progress"}}
           ]
         }}
      end)

      assert {:error, {:jira_transition_not_found, "Unknown State"}} =
               Adapter.update_issue_state("SYM-3", "Unknown State")
    end

    test "returns error when transitions GET fails" do
      Process.put(:stub_client_handler, fn :get, "/rest/api/3/issue/SYM-5/transitions", _body ->
        {:error, {:jira_api_status, 500}}
      end)

      assert {:error, {:jira_api_status, 500}} =
               Adapter.update_issue_state("SYM-5", "Done")
    end
  end
end
