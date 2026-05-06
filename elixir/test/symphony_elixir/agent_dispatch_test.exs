defmodule SymphonyElixir.AgentDispatchTest do
  use ExUnit.Case, async: false

  test "Agent.impl/0 returns Codex.AppServer by default" do
    Application.delete_env(:symphony_elixir, :agent_kind_override)
    assert SymphonyElixir.Agent.impl() == SymphonyElixir.Codex.AppServer
  end

  test "Agent.impl/0 returns ClaudeCode.AppServer when kind override is claude_code" do
    Application.put_env(:symphony_elixir, :agent_kind_override, "claude_code")
    assert SymphonyElixir.Agent.impl() == SymphonyElixir.ClaudeCode.AppServer
  after
    Application.delete_env(:symphony_elixir, :agent_kind_override)
  end

  test "ClaudeCode.AppServer implements Agent behaviour" do
    assert SymphonyElixir.ClaudeCode.AppServer.__info__(:functions)
           |> Keyword.has_key?(:start_session)
  end
end
