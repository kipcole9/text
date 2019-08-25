defmodule LangDetectTest do
  use ExUnit.Case
  doctest LangDetect

  test "greets the world" do
    assert LangDetect.hello() == :world
  end
end
