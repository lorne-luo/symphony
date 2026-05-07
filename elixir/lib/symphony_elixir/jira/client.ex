defmodule SymphonyElixir.Jira.Client do
  @moduledoc """
  Thin Jira REST API client for polling candidate issues via JQL.

  Returns canonical `SymphonyElixir.Linear.Issue` structs so the rest of the
  orchestrator can remain tracker-agnostic.
  """

  require Logger
  alias SymphonyElixir.Linear.Issue

  @issue_page_size 50
  @search_fields "summary,description,priority,status,assignee,labels,issuelinks,created,updated"

  @spec fetch_candidate_issues() :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues do
    tracker = settings().tracker

    cond do
      is_nil(tracker.api_key) ->
        {:error, :missing_jira_api_token}

      is_nil(tracker.email) ->
        {:error, :missing_jira_email}

      is_nil(tracker.project_key) ->
        {:error, :missing_jira_project_key}

      true ->
        fetch_issues_by_states(tracker.active_states)
    end
  end

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(state_names) when is_list(state_names) do
    normalized = state_names |> Enum.map(&to_string/1) |> Enum.uniq()

    if normalized == [] do
      {:ok, []}
    else
      tracker = settings().tracker

      cond do
        is_nil(tracker.api_key) ->
          {:error, :missing_jira_api_token}

        is_nil(tracker.email) ->
          {:error, :missing_jira_email}

        is_nil(tracker.project_key) ->
          {:error, :missing_jira_project_key}

        true ->
          status_clause =
            normalized
            |> Enum.map_join(" OR ", fn s -> ~s(status = "#{s}") end)

          assignee_clause =
            if is_binary(tracker.assignee) and tracker.assignee != "",
              do: " AND assignee = \"#{tracker.assignee}\"",
              else: ""

          jql = "project = \"#{tracker.project_key}\" AND (#{status_clause})#{assignee_clause} ORDER BY created ASC"
          do_fetch_all(jql, 0, [])
      end
    end
  end

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids) when is_list(issue_ids) do
    ids = Enum.uniq(issue_ids)

    case ids do
      [] ->
        {:ok, []}

      ids ->
        tracker = settings().tracker

        cond do
          is_nil(tracker.api_key) ->
            {:error, :missing_jira_api_token}

          is_nil(tracker.email) ->
            {:error, :missing_jira_email}

          true ->
            results =
              Enum.map(ids, fn id ->
                path = "/rest/api/3/issue/#{id}?fields=#{@search_fields}"
                case do_request(:get, path, nil, []) do
                  {:ok, issue} -> normalize_issue(issue)
                  _ -> nil
                end
              end)
              |> Enum.reject(&is_nil/1)
            {:ok, results}
        end
    end
  end

  @spec request(:get | :post, String.t(), map() | nil) :: {:ok, map()} | {:error, term()}
  def request(method, path, body \\ nil) do
    do_request(method, path, body, [])
  end

  @doc false
  @spec normalize_issue_for_test(map()) :: Issue.t() | nil
  def normalize_issue_for_test(issue) when is_map(issue), do: normalize_issue(issue)

  defp do_fetch_all(jql, start_at, acc) do
    tracker = settings().tracker

    path =
      if is_binary(tracker.board_id) and tracker.board_id != "" do
        params = %{
          jql: jql,
          startAt: start_at,
          maxResults: @issue_page_size,
          fields: @search_fields
        }
        "/rest/agile/1.0/board/#{tracker.board_id}/issue?" <> URI.encode_query(params)
      else
        params = %{
          jql: jql,
          startAt: start_at,
          maxResults: @issue_page_size,
          fields: @search_fields
        }
        "/rest/api/3/search?" <> URI.encode_query(params)
      end

    case do_request(:get, path, nil, []) do
      {:ok, %{"issues" => issues, "total" => total}} when is_list(issues) ->
        parsed = Enum.map(issues, &normalize_issue/1) |> Enum.reject(&is_nil/1)
        updated_acc = prepend_page_issues(parsed, acc)
        fetched_so_far = start_at + length(issues)

        if fetched_so_far < total and length(issues) > 0 do
          do_fetch_all(jql, fetched_so_far, updated_acc)
        else
          {:ok, finalize_paginated_issues(updated_acc)}
        end

      {:ok, body} ->
        Logger.error("Jira search returned unexpected body: #{inspect(body, limit: 20)}")
        {:error, :jira_unexpected_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp prepend_page_issues(issues, acc) when is_list(issues) and is_list(acc) do
    Enum.reverse(issues, acc)
  end

  defp finalize_paginated_issues(acc) when is_list(acc), do: Enum.reverse(acc)

  defp do_request(method, path, body, _opts) do
    tracker = settings().tracker
    endpoint = tracker.endpoint || ""
    url = endpoint <> path

    credentials = Base.encode64("#{tracker.email}:#{tracker.api_key}")

    headers = [
      {"Authorization", "Basic #{credentials}"},
      {"Accept", "application/json"},
      {"Content-Type", "application/json"}
    ]

    result =
      case method do
        :get ->
          Req.get(url, headers: headers, connect_options: [timeout: 30_000])

        :post ->
          Req.post(url, headers: headers, json: body, connect_options: [timeout: 30_000])
      end

    case result do
      {:ok, %{status: status, body: resp_body}} when status in 200..299 ->
        {:ok, resp_body}

      {:ok, %{status: status}} ->
        Logger.error("Jira API returned status #{status} for #{method} #{path}")
        {:error, {:jira_api_status, status}}

      {:error, reason} ->
        Logger.error("Jira API request failed: #{inspect(reason)}")
        {:error, {:jira_api_request, reason}}
    end
  end

  defp normalize_issue(issue) when is_map(issue) do
    key = issue["key"]
    fields = issue["fields"] || %{}

    %Issue{
      id: key,
      identifier: key,
      title: fields["summary"],
      description: description_to_string(fields["description"]),
      priority: parse_priority(get_in(fields, ["priority", "id"])),
      state: get_in(fields, ["status", "name"]),
      branch_name: build_branch_name(key, fields["summary"]),
      url: "#{settings().tracker.endpoint}/browse/#{key}",
      assignee_id: get_in(fields, ["assignee", "accountId"]),
      labels: extract_labels(fields["labels"]),
      blocked_by: extract_blockers(fields["issuelinks"]),
      assigned_to_worker: true,
      created_at: parse_datetime(fields["created"]),
      updated_at: parse_datetime(fields["updated"])
    }
  end

  defp normalize_issue(_issue), do: nil

  defp description_to_string(nil), do: nil
  defp description_to_string(desc) when is_binary(desc), do: desc

  defp description_to_string(desc) when is_map(desc) do
    case Jason.encode(desc) do
      {:ok, json} -> json
      _ -> nil
    end
  end

  defp description_to_string(_), do: nil

  defp parse_priority(nil), do: nil

  defp parse_priority(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_priority(id) when is_integer(id), do: id
  defp parse_priority(_), do: nil

  defp extract_labels(labels) when is_list(labels) do
    labels
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.downcase/1)
  end

  defp extract_labels(_), do: []

  defp extract_blockers(issuelinks) when is_list(issuelinks) do
    issuelinks
    |> Enum.flat_map(fn link ->
      inward_name = get_in(link, ["type", "inward"])

      if is_binary(inward_name) and String.downcase(inward_name) == "is blocked by" do
        case link["inwardIssue"] do
          %{"key" => blocker_key} = blocker_issue ->
            [
              %{
                id: blocker_key,
                identifier: blocker_key,
                state: get_in(blocker_issue, ["fields", "status", "name"])
              }
            ]

          _ ->
            []
        end
      else
        []
      end
    end)
  end

  defp extract_blockers(_), do: []

  defp build_branch_name(nil, _summary), do: nil
  defp build_branch_name(key, nil), do: String.downcase(key)

  defp build_branch_name(key, summary) do
    slug =
      summary
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.slice(0, 40)
      |> String.trim_trailing("-")

    "#{String.downcase(key)}-#{slug}"
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(raw) when is_binary(raw) do
    case DateTime.from_iso8601(raw) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil

  defp settings do
    Application.get_env(:symphony_elixir, :test_config) || SymphonyElixir.Config.settings!()
  end
end
