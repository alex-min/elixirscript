defmodule ElixirScript.FindUsedModules do
  @moduledoc false
  alias ElixirScript.State, as: ModuleState
  require Logger

  @doc """
  Takes a list of entry modules and finds modules they use.
  """
  @spec execute([atom], pid) :: :ok
  def execute(modules, pid) do
    modules
    |> List.wrap()
    |> Enum.each(fn module ->
      do_execute(module, pid)
    end)
  end

  defp do_execute(module, result, pid) do
    case result do
      {:ok, info} ->
        walk_module(module, info, pid)

      {:ok, module, module_info, implementations} ->
        walk_protocol(module, module_info, implementations, pid)

      {:error, "Unknown module"} ->
        Logger.warn(fn ->
          "ElixirScript: #{inspect(module)} is missing or unavailable"
        end)

        ModuleState.put_diagnostic(pid, module, %{
          severity: :warning,
          message: "#{inspect(module)} is missing or unavailable"
        })

      {:error, error} ->
        raise ElixirScript.CompileError,
          message: "An error occurred while compiling #{inspect(module)}: #{error}",
          severity: :error
    end
  end

  defp do_execute(module, pid) do
    result = get_debug_info(module, pid)
    do_execute(module, result, pid)
  end

  defp get_debug_info(module, pid) do
    case ModuleState.get_in_memory_module(pid, module) do
      nil ->
        ElixirScript.Beam.debug_info(module)

      beam ->
        ElixirScript.Beam.debug_info(beam)
    end
  end

  defp walk_module(
         module,
         %{attributes: [__foreign_info__: %{path: path, name: name, global: global}]} = info,
         pid
       ) do
    {name, path} =
      if global do
        name = if name, do: name, else: module
        path = nil
        {name, path}
      else
        name = Enum.join(Module.split(module), "_")
        path = path <> ".js"
        {name, path}
      end

    ModuleState.put_javascript_module(pid, module, name, path)
    ModuleState.put_module(pid, module, info)

    nil
  end

  defp walk_module(module, info, pid) do
    %{
      attributes: _attrs,
      compile_opts: _compile_opts,
      definitions: defs,
      file: _file,
      line: _line,
      module: ^module,
      unreachable: unreachable
    } = info

    ModuleState.put_module(pid, module, info)

    reachable_defs =
      Enum.filter(defs, fn
        {_, type, _, _} when type in [:defmacro, :defmacrop] -> false
        {name, _, _, _} -> name not in unreachable
        _ -> true
      end)

    state = %{
      pid: pid,
      module: module
    }

    Enum.each(reachable_defs, fn x ->
      walk(x, state)
    end)
  end

  defp walk_protocol(module, module_info, implementations, pid) do
    impls =
      Enum.map(implementations, fn {impl, %{attributes: attrs}} ->
        protocol_impl = Keyword.fetch!(attrs, :protocol_impl)
        impl_for = Keyword.fetch!(protocol_impl, :for)
        {impl, impl_for}
      end)

    first_implementation_functions = implementations |> hd |> elem(1) |> Map.get(:definitions)

    functions = Enum.map(first_implementation_functions, fn {name, _, _, _} -> name end)

    module_info = Map.merge(module_info, %{protocol: true, impls: impls, functions: functions})

    ModuleState.put_module(pid, module, module_info)

    Enum.each(implementations, fn {impl, info} ->
      ModuleState.put_used_module(pid, module, impl)
      walk_module(impl, info, pid)
    end)
  end

  defp walk({{_name, _arity}, _type, _, clauses}, state) do
    Enum.each(clauses, &walk(&1, state))
  end

  defp walk({_, args, guards, body}, state) do
    walk(args, state)
    walk(guards, state)
    walk_block(body, state)
  end

  defp walk({:->, _, [[{:when, _, params}], body]}, state) do
    guards = List.last(params)
    params = params |> Enum.reverse() |> tl |> Enum.reverse()

    walk({[], params, guards, body}, state)
  end

  defp walk({:->, _, [params, body]}, state) do
    walk({[], params, [], body}, state)
  end

  defp walk({:|, _, [head, tail]}, state) do
    walk(head, state)
    walk(tail, state)
  end

  defp walk({:"::", _, [target, _type]}, state) do
    walk(target, state)
  end

  defp walk(form, state) when is_list(form) do
    Enum.each(form, &walk(&1, state))
  end

  defp walk(form, state)
       when is_atom(form) and form not in [BitString, Function, PID, Port, Reference, Any, Elixir] do
    if ElixirScript.Translate.Module.is_elixir_module(form) and
         !ElixirScript.Translate.Module.is_js_module(form, state) do
      if ModuleState.get_module(state.pid, form) == nil do
        case get_debug_info(form, state.pid) do
          {:ok, _} = result ->
            ModuleState.put_used_module(state.pid, state.module, form)
            do_execute(form, result, state.pid)

          result ->
            do_execute(form, result, state.pid)
        end
      else
        ModuleState.put_used_module(state.pid, state.module, form)
      end
    end
  end

  defp walk({a, b}, state) do
    walk({:{}, [], [a, b]}, state)
  end

  defp walk({:{}, _, elements}, state) do
    Enum.each(elements, &walk(&1, state))
  end

  defp walk({:%{}, _, properties}, state) do
    Enum.each(properties, fn val -> walk(val, state) end)
  end

  defp walk({:<<>>, _, elements}, state) do
    Enum.each(elements, fn val -> walk(val, state) end)
  end

  defp walk({:=, _, [left, right]}, state) do
    walk(left, state)
    walk(right, state)
  end

  defp walk({:%, _, [module, params]}, state) do
    if ElixirScript.Translate.Module.is_elixir_module(module) and
         !ElixirScript.Translate.Module.is_js_module(module, state) do
      if ModuleState.get_module(state.pid, module) == nil do
        case get_debug_info(module, state.pid) do
          {:ok, _} = result ->
            ModuleState.put_used_module(state.pid, state.module, module)
            do_execute(module, result, state.pid)

          result ->
            do_execute(module, result, state.pid)
        end
      else
        ModuleState.put_used_module(state.pid, state.module, module)
      end
    end

    walk(params, state)
  end

  defp walk({:for, _, generators}, state) when is_list(generators) do
    walk(Collectable, state)

    Enum.each(generators, fn
      {:<<>>, _, body} ->
        walk(body, state)

      {:<-, _, [identifier, enum]} ->
        walk(identifier, state)
        walk(enum, state)

      [into: expression] ->
        walk(expression, state)

      [into: expression, do: expression2] ->
        walk(expression, state)
        walk_block(expression2, state)

      [do: expression] ->
        walk_block(expression, state)

      filter ->
        walk(filter, state)
    end)
  end

  defp walk({:case, _, [condition, [do: clauses]]}, state) do
    Enum.each(clauses, &walk(&1, state))
    walk(condition, state)
  end

  defp walk({:cond, _, [[do: clauses]]}, state) do
    Enum.each(clauses, fn {:->, _, [clause, clause_body]} ->
      Enum.each(List.wrap(clause_body), &walk(&1, state))
      walk(hd(clause), state)
    end)
  end

  defp walk({:receive, _context, blocks}, state) when is_list(blocks) do
    do_block = Keyword.get(blocks, :do)
    after_block = Keyword.get(blocks, :after, nil)

    walk_block(do_block, state)

    if after_block do
      Enum.each(List.wrap(after_block), &walk(&1, state))
    end
  end

  defp walk({:try, _, [blocks]}, state) do
    walk(Enum, state)

    try_block = Keyword.get(blocks, :do)
    rescue_block = Keyword.get(blocks, :rescue, nil)
    catch_block = Keyword.get(blocks, :catch, nil)
    after_block = Keyword.get(blocks, :after, nil)
    else_block = Keyword.get(blocks, :else, nil)

    walk_block(try_block, state)

    if rescue_block do
      Enum.each(rescue_block, fn
        {:->, _, [[{:in, _, [param, names]}], body]} ->
          Enum.each(names, &walk(&1, state))
          walk({[], [param], [{{:., [], [Enum, :member?]}, [], [names, param]}], body}, state)

        {:->, _, [[param], body]} ->
          walk({[], [param], [], body}, state)
      end)
    end

    if catch_block do
      walk({:fn, [], catch_block}, state)
    end

    if after_block do
      Enum.each(List.wrap(after_block), &walk(&1, state))
    end

    if else_block do
      walk({:fn, [], else_block}, state)
    end
  end

  defp walk({:fn, _, clauses}, state) do
    Enum.each(clauses, &walk(&1, state))
  end

  defp walk({:with, _, args}, state) do
    Enum.each(args, fn
      {:<-, _, [left, right]} ->
        walk(left, state)
        walk(right, state)

      {:=, _, [left, right]} ->
        walk(left, state)
        walk(right, state)

      [do: expression] ->
        walk_block(expression, state)

      [do: expression, else: elses] ->
        walk_block(expression, state)

        Enum.each(elses, fn {:->, _, [left, right]} ->
          walk(left, state)
          walk(right, state)
        end)
    end)
  end

  defp walk({{:., _, [:erlang, :apply]}, _, [module, function, params]}, state) do
    walk({{:., [], [module, function]}, [], params}, state)
  end

  defp walk({{:., _, [:erlang, :apply]}, _, [function, params]}, state) do
    walk({function, [], params}, state)
  end

  defp walk({{:., _, [_module, _function]} = ast, _, params}, state) do
    walk(ast, state)
    walk(params, state)
  end

  defp walk({:., _, [ElixirScript.JS, _]}, _) do
    nil
  end

  defp walk({:., _, [module, function]}, state) do
    if ElixirScript.Translate.Module.is_elixir_module(module) do
      if ModuleState.get_module(state.pid, module) == nil do
        case get_debug_info(module, state.pid) do
          {:ok, _} = result ->
            ModuleState.put_used_module(state.pid, state.module, module)
            do_execute(module, result, state.pid)

          result ->
            do_execute(module, result, state.pid)
        end
      else
        ModuleState.put_used_module(state.pid, state.module, module)
      end
    else
      walk(module, state)
      walk(function, state)
    end
  end

  defp walk({:super, _, [{_, _} | params]}, state) do
    walk(params, state)
  end

  defp walk({function, _, params}, state) when is_list(params) do
    walk(function, state)
    walk(params, state)
  end

  defp walk(_, _) do
    nil
  end

  defp walk_block(block, state) do
    case block do
      nil ->
        nil

      {:__block__, _, block_body} ->
        Enum.each(block_body, &walk(&1, state))

      b when is_list(b) ->
        Enum.each(b, &walk(&1, state))

      _ ->
        walk(block, state)
    end
  end
end
