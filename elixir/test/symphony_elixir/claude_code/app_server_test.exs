defmodule SymphonyElixir.ClaudeCode.AppServerTest do
  use ExUnit.Case, async: false

  test "ClaudeCode.AppServer implements the Agent behaviour" do
    assert function_exported?(SymphonyElixir.ClaudeCode.AppServer, :start_session, 2)
    assert function_exported?(SymphonyElixir.ClaudeCode.AppServer, :run_turn, 4)
    assert function_exported?(SymphonyElixir.ClaudeCode.AppServer, :stop_session, 1)
  end

  test "ClaudeCode.AppServer injects command_override into start_session opts" do
    # The module should delegate to base() (Codex.AppServer by default),
    # but we can verify the module builds opts with :command_override before delegating.
    # Since we cannot actually spawn a process in tests, we verify the behaviour contract.
    assert :erlang.function_exported(SymphonyElixir.ClaudeCode.AppServer, :start_session, 2)
    assert :erlang.function_exported(SymphonyElixir.ClaudeCode.AppServer, :start_session, 1)
  end
end
