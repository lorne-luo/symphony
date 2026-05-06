defmodule SymphonyElixir.ClaudeCode.AppServer do
  @moduledoc "Claude Code agent (delegates to Python shim via Codex JSON-RPC protocol)."
  @behaviour SymphonyElixir.Agent

  @impl true
  def start_session(_workspace, _opts), do: {:error, :not_implemented}

  @impl true
  def run_turn(_session, _prompt, _issue, _opts), do: {:error, :not_implemented}

  @impl true
  def stop_session(_session), do: :ok
end
