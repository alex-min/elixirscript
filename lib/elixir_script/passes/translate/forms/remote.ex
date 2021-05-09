defmodule ElixirScript.Translate.Forms.Remote do
  @moduledoc false

  alias ESTree.Tools.Builder, as: J
  alias ElixirScript.Translate.{Form, Helpers}
  alias ElixirScript.State, as: ModuleState

  @erlang_modules [
    :erlang,
    :maps,
    :lists,
    :gen,
    :elixir_errors,
    :elixir_config,
    :supervisor,
    :application,
    :code,
    :elixir_utils,
    :file,
    :io,
    :binary,
    :unicode,
    :math,
    :calendar,
    :filename,
    :epp,
    :re,
    :ets,
    :sys,
    :global,
    :os,
    :rand,
    :orddict,
    :filelib,
    :net_adm,
    :net_kernel,
    IO
  ]

  @doc """
  Compiles functions into JavaScript AST.
  These are not actual function calls, but
  the function identifiers themselves. Also
  includes function heads for converting some
  erlang functions into JavaScript functions.
  """

  def compile({:., _, [:erlang, :++]}, state) do
    ast = erlang_compat_function("erlang", "list_concatenation")
    {ast, state}
  end

  def compile({:., _, [:erlang, :--]}, state) do
    ast = erlang_compat_function("erlang", "list_substraction")
    {ast, state}
  end

  def compile({:., _, [:erlang, :"=<"]}, state) do
    ast = erlang_compat_function("erlang", "lessThanEqualTo")
    {ast, state}
  end

  def compile({:., _, [:erlang, :+]}, state) do
    ast = erlang_compat_function("erlang", "add")
    {ast, state}
  end

  def compile({:., _, [module, function]}, state) when module in @erlang_modules do
    ast =
      J.member_expression(
        Helpers.core_module(module),
        J.identifier(function)
      )

    {ast, state}
  end

  def compile({:., _, [function_name]}, state) do
    Form.compile(function_name, state)
  end

  def compile({:., _, [module, function]}, state) do
    function_name = ElixirScript.Translate.Identifier.make_function_name(function)

    ast =
      J.member_expression(
        process_module_name(module, state),
        function_name
      )

    {ast, state}
  end

  def process_module_name(module, state) when is_atom(module) do
    cond do
      ElixirScript.Translate.Module.is_js_module(module, state) and
          ModuleState.is_global_module(state.pid, module) ->
        process_global_js_module_name(module, state)

      ElixirScript.Translate.Module.is_js_module(module, state) ->
        process_js_module_name(module, state)

      module === Elixir ->
        module
        |> ElixirScript.Output.module_to_name()
        |> J.identifier()

      module === :ElixirScript ->
        module
        |> ElixirScript.Output.module_to_name()
        |> J.identifier()

      ElixirScript.Translate.Module.is_elixir_module(module) ->
        module
        |> ElixirScript.Output.module_to_name()
        |> J.identifier()

      true ->
        ElixirScript.Translate.Identifier.make_identifier(module)
    end
  end

  def process_module_name(module, state) do
    Form.compile!(module, state)
  end

  defp process_global_js_module_name(module, state) do
    case ModuleState.get_js_module_name(state.pid, module) do
      name when is_binary(name) ->
        J.identifier(name)

      name when is_atom(name) ->
        case to_string(name) do
          "Elixir." <> _ ->
            ElixirScript.Translate.Identifier.make_alias(Module.split(name) |> Enum.reverse())

          x ->
            J.identifier(x)
        end
    end
  end

  defp process_js_module_name(module, state) do
    case ModuleState.get_js_module_name(state.pid, module) do
      name when is_binary(name) ->
        J.identifier(name)

      name when is_atom(name) ->
        case to_string(name) do
          "Elixir." <> _ ->
            module
            |> ElixirScript.Output.module_to_name()
            |> J.identifier()

          x ->
            J.identifier(x)
        end
    end
  end

  defp erlang_compat_function(module, function) do
    J.member_expression(
      Helpers.core_module(module),
      ElixirScript.Translate.Identifier.make_function_name(function)
    )
  end
end
