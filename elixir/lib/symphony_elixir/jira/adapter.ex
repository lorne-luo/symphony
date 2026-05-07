defmodule SymphonyElixir.Jira.Adapter do
  @moduledoc """
  Jira-backed tracker adapter.
  """

  @behaviour SymphonyElixir.Tracker

  alias SymphonyElixir.Jira.Client

  @impl true
  @spec fetch_candidate_issues() :: {:ok, [term()]} | {:error, term()}
  def fetch_candidate_issues, do: client_module().fetch_candidate_issues()

  @impl true
  @spec fetch_issues_by_states([String.t()]) :: {:ok, [term()]} | {:error, term()}
  def fetch_issues_by_states(states), do: client_module().fetch_issues_by_states(states)

  @impl true
  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [term()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids), do: client_module().fetch_issue_states_by_ids(issue_ids)

  @impl true
  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(issue_key, body) when is_binary(issue_key) and is_binary(body) do
    adf_body = %{
      "body" => %{
        "type" => "doc",
        "version" => 1,
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [%{"type" => "text", "text" => body}]
          }
        ]
      }
    }

    case client_module().request(:post, "/rest/api/3/issue/#{issue_key}/comment", adf_body) do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(issue_key, state_name)
      when is_binary(issue_key) and is_binary(state_name) do
    with {:ok, transition_id} <- find_transition_id(issue_key, state_name),
         {:ok, _response} <-
           client_module().request(:post, "/rest/api/3/issue/#{issue_key}/transitions", %{
             transition: %{id: transition_id}
           }) do
      :ok
    end
  end

  defp client_module do
    Application.get_env(:symphony_elixir, :jira_client_module, Client)
  end

  defp find_transition_id(issue_key, state_name) do
    case client_module().request(:get, "/rest/api/3/issue/#{issue_key}/transitions") do
      {:ok, %{"transitions" => transitions}} when is_list(transitions) ->
        normalized = String.downcase(state_name)

        case Enum.find(transitions, fn t ->
               String.downcase(get_in(t, ["to", "name"]) || "") == normalized
             end) do
          %{"id" => id} -> {:ok, id}
          nil -> {:error, {:jira_transition_not_found, state_name}}
        end

      {:ok, _unexpected} ->
        {:error, {:jira_transition_not_found, state_name}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
