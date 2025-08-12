defmodule AlternativeServer.HelloWorldTest do
  use ExUnit.Case

  test "hello world!" do
    assert hello_world() == "Hello, World!"
  end

  defp hello_world do
    "Hello, World!"
  end
end