defmodule SymphonyElixir.Agent do
  @moduledoc "Behaviour for execution agents (Codex, Claude Code, etc.)."

  @type session :: map()
  @type opts :: keyword()
  @type issue :: map()

  @callback start_session(Path.t(), opts) :: {:ok, session} | {:error, term}
  @callback run_turn(session, String.t(), issue, opts) :: {:ok, map} | {:error, term}
  @callback stop_session(session) :: :ok

  @spec impl() :: module()
  def impl do
    case agent_kind() do
      "claude_code" -> SymphonyElixir.ClaudeCode.AppServer
      _ -> SymphonyElixir.Codex.AppServer
    end
  end

  defp agent_kind do
    Application.get_env(:symphony_elixir, :agent_kind_override) ||
      SymphonyElixir.Config.settings!().app_server.kind
  end
end
