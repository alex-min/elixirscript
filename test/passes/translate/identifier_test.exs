defmodule ElixirScript.Translate.Identifier.Test do
  use ExUnit.Case
  alias ElixirScript.Translate.Identifier

  test "transform function names with invalid chars" do
    assert Identifier.filter_name("hello world?") == "hello_world__qmark__"
  end

  test "filters reserved keywords" do
    assert Identifier.filter_name("while") == "__while__"
  end
end
