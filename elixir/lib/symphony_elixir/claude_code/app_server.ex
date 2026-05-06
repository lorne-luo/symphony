defmodule SymphonyElixir.ClaudeCode.AppServer do
  @moduledoc "Claude Code agent — delegates to Python shim via Codex JSON-RPC protocol."
  @behaviour SymphonyElixir.Agent

  @impl true
  def start_session(workspace, opts \\ []) do
    opts = Keyword.put_new(opts, :command_override, default_command())
    base().start_session(workspace, opts)
  end

  @impl true
  def run_turn(session, prompt, issue, opts \\ []), do: base().run_turn(session, prompt, issue, opts)

  @impl true
  def stop_session(session), do: base().stop_session(session)

  defp base do
    Application.get_env(:symphony_elixir, :codex_app_server_module, SymphonyElixir.Codex.AppServer)
  end

  defp default_command do
    SymphonyElixir.Config.settings!().app_server.command || "python -m claude_app_server"
  rescue
    _ -> "python -m claude_app_server"
  end
end
