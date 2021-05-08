defmodule ElixirScript.Translate.Forms.Try do
  @moduledoc false
  alias ESTree.Tools.Builder, as: JS
  alias ElixirScript.Translate.{Form, Function, Clause, Helpers}

  def compile(blocks, state) do
    try_block = Keyword.get(blocks, :do)
    rescue_block = Keyword.get(blocks, :rescue, nil)
    catch_block = Keyword.get(blocks, :catch, nil)
    after_block = Keyword.get(blocks, :after, nil)
    else_block = Keyword.get(blocks, :else, nil)

    translated_body = prepare_function_body(try_block, state)

    translated_body = JS.block_statement(translated_body)
    try_block = Helpers.arrow_function([], translated_body)

    rescue_block =
      if rescue_block do
        process_rescue_block(rescue_block, state)
      else
        JS.identifier(:null)
      end

    catch_block =
      if catch_block do
        Form.compile!({:fn, [], catch_block}, state)
      else
        JS.identifier(:null)
      end

    after_block =
      if after_block do
        process_after_block(after_block, state)
      else
        JS.identifier(:null)
      end

    else_block =
      if else_block do
        Form.compile!({:fn, [], else_block}, state)
      else
        JS.identifier(:null)
      end

    js_ast =
      Helpers.call(
        JS.member_expression(
          Helpers.special_forms(),
          JS.identifier("_try")
        ),
        [
          try_block,
          rescue_block,
          catch_block,
          else_block,
          after_block
        ]
      )

    {js_ast, state}
  end

  defp process_rescue_block(rescue_block, state) do
    processed_clauses =
      Enum.map(rescue_block, fn
        {:->, _, [[{:in, _, [{:_, context, atom}, names]}], body]} ->
          names = Enum.map(names, &make_exception_ast(&1))

          param = {:_e, context, atom}
          reason_call = {{:., [], [param, :__reason]}, [], []}
          reason_call = {{:., [], [reason_call, :__struct__]}, [], []}
          reason_call = {{:., [], [reason_call, :__MODULE__]}, [], []}

          {ast, _} =
            Clause.compile(
              {
                [],
                [param],
                [{{:., [], [Enum, :member?]}, [], [names, reason_call]}],
                body
              },
              state
            )

          ast

        {:->, _, [[{:in, _, [param, names]}], body]} ->
          names = Enum.map(names, &make_exception_ast(&1))

          reason_call = {{:., [], [param, :__reason]}, [], []}
          reason_call = {{:., [], [reason_call, :__struct__]}, [], []}
          reason_call = {{:., [], [reason_call, :__MODULE__]}, [], []}

          {ast, _} =
            Clause.compile(
              {
                [],
                [param],
                [{{:., [], [Enum, :member?]}, [], [names, reason_call]}],
                body
              },
              state
            )

          ast

        {:->, _, [[param], body]} ->
          {ast, _} = Clause.compile({[], [param], [], body}, state)
          ast
      end)

    Helpers.call(
      JS.member_expression(
        Helpers.patterns(),
        JS.identifier("defmatch")
      ),
      processed_clauses
    )
  end

  defp make_exception_ast(name) do
    {{:., [], [name, :__MODULE__]}, [], []}
  end

  defp process_after_block(after_block, state) do
    translated_body = prepare_function_body(after_block, state)
    translated_body = JS.block_statement(translated_body)

    Helpers.arrow_function([], translated_body)
  end

  defp prepare_function_body(body, state) do
    {ast, _} = Function.compile_block(body, state)

    Clause.return_last_statement(ast)
  end
end
