defmodule LiveLift.Client.Compiler do
  @moduledoc """
  Compiles LiveLift's deliberately small pure expression subset to JavaScript.

  Unsupported Elixir syntax raises instead of silently changing semantics.
  """

  @max_safe_integer 9_007_199_254_740_991
  @identifier ~r/^[a-zA-Z_$][a-zA-Z0-9_$]*$/
  @reserved ~w(__proto__ prototype constructor)

  @helpers ~S"""
  function __liveLiftInt(value) {
    if (!Number.isSafeInteger(value)) throw new Error("LiveLift expected a safe integer");
    return value;
  }
  function __liveLiftFloatText(value) {
    if (!Number.isFinite(value)) throw new Error("LiveLift expected a finite float");
    if (Object.is(value, -0)) return "-0.0";
    const raw = String(value);
    let fixed;
    if (!raw.includes("e")) {
      fixed = raw.includes(".") ? raw : `${raw}.0`;
    } else {
      let [mantissa, exponent] = raw.split("e");
      const sign = mantissa.startsWith("-") ? "-" : "";
      mantissa = mantissa.replace("-", "");
      const dot = mantissa.indexOf(".");
      const digits = mantissa.replace(".", "");
      const position = (dot < 0 ? mantissa.length : dot) + Number(exponent);
      fixed = position <= 0 ? `0.${"0".repeat(-position)}${digits}` :
        position >= digits.length ? `${digits}${"0".repeat(position - digits.length)}.0` :
          `${digits.slice(0, position)}.${digits.slice(position)}`;
      fixed = sign + fixed;
    }
    let [mantissa, exponent] = value.toExponential().split("e");
    exponent = Number(exponent);
    const scientific = `${mantissa.includes(".") ? mantissa : `${mantissa}.0`}e${exponent}`;
    return exponent >= 16 || exponent <= -5 || scientific.length < fixed.length ? scientific : fixed;
  }
  function __liveLiftFloat(value) {
    return {$live_lift_float: __liveLiftFloatText(value)};
  }
  function __liveLiftIsFloat(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value) &&
      Object.keys(value).length === 1 && Object.hasOwn(value, "$live_lift_float");
  }
  function __liveLiftNumber(value) {
    if (__liveLiftIsFloat(value)) return Number(value.$live_lift_float);
    return __liveLiftInt(value);
  }
  function __liveLiftArithmetic(left, right, operation) {
    const float = __liveLiftIsFloat(left) || __liveLiftIsFloat(right);
    left = __liveLiftNumber(left);
    right = __liveLiftNumber(right);
    const result = operation === "+" ? left + right : operation === "-" ? left - right : left * right;
    return float ? __liveLiftFloat(result) : __liveLiftInt(result);
  }
  function __liveLiftUnary(value, operation) {
    const float = __liveLiftIsFloat(value);
    const result = operation === "-" ? -__liveLiftNumber(value) : +__liveLiftNumber(value);
    return float ? __liveLiftFloat(result) : __liveLiftInt(result);
  }
  function __liveLiftGet(value, key) {
    if (value === null || typeof value !== "object" || __liveLiftIsFloat(value) || !Object.hasOwn(value, key)) {
      throw new Error(`Missing LiveLift field: ${key}`);
    }
    return value[key];
  }
  function __liveLiftEqual(left, right) {
    if (__liveLiftIsFloat(left) || __liveLiftIsFloat(right)) {
      if (!(typeof left === "number" || __liveLiftIsFloat(left)) ||
          !(typeof right === "number" || __liveLiftIsFloat(right))) return false;
      return __liveLiftNumber(left) === __liveLiftNumber(right);
    }
    if (left === right) return true;
    if (left === null || right === null || typeof left !== typeof right) return false;
    if (typeof left !== "object" || Array.isArray(left) !== Array.isArray(right)) return false;
    if (Array.isArray(left)) {
      return left.length === right.length && left.every((item, index) => __liveLiftEqual(item, right[index]));
    }
    const keys = Object.keys(left);
    return keys.length === Object.keys(right).length &&
      keys.every((key) => Object.hasOwn(right, key) && __liveLiftEqual(left[key], right[key]));
  }
  function __liveLiftTruthy(value) { return value !== false && value !== null; }
  function __liveLiftCondFailure() { throw new Error("LiveLift cond has no true clause"); }
  function __liveLiftCaseFailure() { throw new Error("LiveLift case has no matching clause"); }
  function __liveLiftHelperFailure(name) { throw new Error(`LiveLift helper has no matching clause: ${name}`); }
  function __liveLiftMatch(value, pattern, bindings) {
    if (pattern.type === "wildcard") return true;
    if (pattern.type === "variable") {
      bindings[pattern.name] = value;
      return true;
    }
    if (pattern.type === "alias") {
      return __liveLiftMatch(value, pattern.left, bindings) &&
        __liveLiftMatch(value, pattern.right, bindings);
    }
    if (pattern.type === "literal") {
      const literal = pattern.value;
      if (__liveLiftIsFloat(value) || __liveLiftIsFloat(literal)) {
        return __liveLiftIsFloat(value) && __liveLiftIsFloat(literal) &&
          value.$live_lift_float === literal.$live_lift_float;
      }
      return value === literal;
    }
    if (pattern.type === "list") {
      return Array.isArray(value) && value.length === pattern.items.length &&
        pattern.items.every((item, index) => __liveLiftMatch(value[index], item, bindings));
    }
    if (pattern.type === "cons") {
      return Array.isArray(value) && value.length > 0 &&
        __liveLiftMatch(value[0], pattern.head, bindings) &&
        __liveLiftMatch(value.slice(1), pattern.tail, bindings);
    }
    if (pattern.type === "map") {
      return value !== null && typeof value === "object" && !Array.isArray(value) &&
        !__liveLiftIsFloat(value) && pattern.entries.every(([key, item]) =>
          Object.hasOwn(value, key) && __liveLiftMatch(value[key], item, bindings));
    }
    throw new Error(`Unknown LiveLift case pattern: ${pattern.type}`);
  }
  function __liveLiftList(value) {
    if (!Array.isArray(value)) throw new Error("LiveLift expected a list");
    return value;
  }
  function __liveLiftMap(value) {
    if (!value || typeof value !== "object" || Array.isArray(value) || __liveLiftIsFloat(value)) {
      throw new Error("LiveLift expected a map");
    }
    return value;
  }
  function __liveLiftMapPut(map, key, value) {
    map = __liveLiftMap(map);
    return {...map, [key]: value};
  }
  function __liveLiftMapUpdate(map, updates) {
    map = __liveLiftMap(map);
    for (const key of Object.keys(updates)) {
      if (!Object.hasOwn(map, key)) throw new Error(`Missing LiveLift map key: ${key}`);
    }
    return {...map, ...updates};
  }
  function __liveLiftAssignNew(map, key, fallback) {
    map = __liveLiftMap(map);
    return Object.hasOwn(map, key) ? map : {...map, [key]: fallback()};
  }
  function __liveLiftMapGet(map, key, fallback) {
    map = __liveLiftMap(map);
    return Object.hasOwn(map, key) ? map[key] : fallback;
  }
  function __liveLiftMapMerge(left, right) {
    return {...__liveLiftMap(left), ...__liveLiftMap(right)};
  }
  function __liveLiftMapDelete(map, key) {
    map = __liveLiftMap(map);
    const result = {...map};
    delete result[key];
    return result;
  }
  function __liveLiftMapTake(map, keys) {
    map = __liveLiftMap(map);
    const result = {};
    for (const key of keys) {
      if (Object.hasOwn(map, key)) result[key] = map[key];
    }
    return result;
  }
  function __liveLiftRem(left, right) {
    left = __liveLiftInt(left);
    right = __liveLiftInt(right);
    if (right === 0) throw new Error("LiveLift division by zero");
    return __liveLiftInt(left % right);
  }
  function __liveLiftString(value) {
    if (typeof value !== "string") throw new Error("LiveLift expected a string");
    return value;
  }
  function __liveLiftContains(value, patterns) {
    const text = __liveLiftString(value);
    if (typeof patterns === "string") return text.includes(patterns);
    if (!Array.isArray(patterns)) throw new Error("LiveLift expected a string or list of strings");
    return patterns.some((pattern) => text.includes(__liveLiftString(pattern)));
  }
  function __liveLiftTrim(value) {
    // Elixir trims U+0085 but leaves U+FEFF; JavaScript trim() does the reverse.
    return __liveLiftString(value).replace(/^[\u0009-\u000D\u0020\u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]+|[\u0009-\u000D\u0020\u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]+$/g, "");
  }
  let __liveLiftGraphemes;
  function __liveLiftStringLength(value) {
    if (typeof Intl === "undefined" || typeof Intl.Segmenter !== "function") throw new Error("LiveLift requires Intl.Segmenter for String.length/1");
    __liveLiftGraphemes ??= new Intl.Segmenter(undefined, {granularity: "grapheme"});
    let count = 0;
    for (const _segment of __liveLiftGraphemes.segment(__liveLiftString(value))) count += 1;
    return count;
  }
  function __liveLiftAnd(left, right) { return __liveLiftTruthy(left) ? right() : left; }
  function __liveLiftOr(left, right) { return __liveLiftTruthy(left) ? left : right(); }
  function __liveLiftMember(list, value) {
    return __liveLiftList(list).some((item) => __liveLiftEqual(item, value));
  }
  function __liveLiftFind(list, fallback, predicate) {
    for (const item of __liveLiftList(list)) {
      if (__liveLiftTruthy(predicate(item))) return item;
    }
    return fallback;
  }
  function __liveLiftReduce(list, initial, callback, seeded) {
    list = __liveLiftList(list);
    if (!seeded && list.length === 0) throw new Error("LiveLift Enum.reduce/2 requires a nonempty list");
    let accumulator = seeded ? initial : list[0];
    for (let index = seeded ? 0 : 1; index < list.length; index += 1) {
      accumulator = callback(list[index], accumulator);
    }
    return accumulator;
  }
  function __liveLiftStringCompare(left, right) {
    const a = Array.from(left, (character) => character.codePointAt(0));
    const b = Array.from(right, (character) => character.codePointAt(0));
    for (let index = 0; index < Math.min(a.length, b.length); index += 1) {
      if (a[index] !== b[index]) return a[index] < b[index] ? -1 : 1;
    }
    return Math.sign(a.length - b.length);
  }
  function __liveLiftTermRank(value) {
    if (typeof value === "number" || __liveLiftIsFloat(value)) return 0;
    if (value === null || typeof value === "boolean") return 1;
    if (value !== null && typeof value === "object" && !Array.isArray(value)) return 2;
    if (Array.isArray(value)) return 3;
    if (typeof value === "string") return 4;
    throw new Error("LiveLift expected a sortable state value");
  }
  function __liveLiftTermCompare(left, right) {
    const leftRank = __liveLiftTermRank(left);
    const rightRank = __liveLiftTermRank(right);
    if (leftRank !== rightRank) return Math.sign(leftRank - rightRank);
    if (leftRank === 0) return Math.sign(__liveLiftNumber(left) - __liveLiftNumber(right));
    if (leftRank === 1) {
      const name = (value) => value === null ? "nil" : String(value);
      return __liveLiftStringCompare(name(left), name(right));
    }
    if (leftRank === 4) return __liveLiftStringCompare(left, right);
    if (leftRank === 3) {
      for (let index = 0; index < Math.min(left.length, right.length); index += 1) {
        const order = __liveLiftTermCompare(left[index], right[index]);
        if (order !== 0) return order;
      }
      return Math.sign(left.length - right.length);
    }
    const leftKeys = Object.keys(left).sort(__liveLiftStringCompare);
    const rightKeys = Object.keys(right).sort(__liveLiftStringCompare);
    if (leftKeys.length !== rightKeys.length) return Math.sign(leftKeys.length - rightKeys.length);
    for (let index = 0; index < leftKeys.length; index += 1) {
      const order = __liveLiftStringCompare(leftKeys[index], rightKeys[index]);
      if (order !== 0) return order;
    }
    for (const key of leftKeys) {
      const order = __liveLiftTermCompare(left[key], right[key]);
      if (order !== 0) return order;
    }
    return 0;
  }
  function __liveLiftSortBy(list, mapper) {
    const projected = __liveLiftList(list).map((item, index) => ({item, index, key: mapper(item)}));
    projected.sort((left, right) => __liveLiftTermCompare(left.key, right.key) || left.index - right.index);
    return projected.map(({item}) => item);
  }
  function __liveLiftCount(list, predicate) {
    let count = 0;
    for (const item of __liveLiftList(list)) {
      if (__liveLiftTruthy(predicate(item))) count += 1;
    }
    return count;
  }
  function __liveLiftChardata(value) {
    if (typeof value === "string") return value;
    if (typeof value === "number") {
      if (!Number.isSafeInteger(value) || value < 0 || value > 0x10ffff ||
          (value >= 0xd800 && value <= 0xdfff)) throw new Error("LiveLift expected a Unicode code point");
      return String.fromCodePoint(value);
    }
    if (Array.isArray(value)) return value.map(__liveLiftChardata).join("");
    throw new Error("LiveLift expected chardata");
  }
  function __liveLiftJoinValue(value) {
    if (value === null) return "";
    if (typeof value === "string") return value;
    if (typeof value === "boolean") return String(value);
    if (__liveLiftIsFloat(value)) return value.$live_lift_float;
    if (typeof value === "number") return String(__liveLiftInt(value));
    if (Array.isArray(value)) return __liveLiftChardata(value);
    throw new Error("LiveLift Enum.join expects String.Chars values");
  }
  function __liveLiftJoin(list, separator) {
    list = __liveLiftList(list);
    separator = __liveLiftString(separator);
    return list.map(__liveLiftJoinValue).join(separator);
  }
  function __liveLiftTake(list, count) {
    list = __liveLiftList(list);
    count = __liveLiftInt(count);
    return count < 0 ? list.slice(Math.max(list.length + count, 0)) : list.slice(0, count);
  }
  function __liveLiftDrop(list, count) {
    list = __liveLiftList(list);
    count = __liveLiftInt(count);
    return count < 0 ? list.slice(0, Math.max(list.length + count, 0)) : list.slice(count);
  }
  function __liveLiftUniq(list) {
    const output = [];
    for (const item of __liveLiftList(list)) {
      if (!output.some((existing) => __liveLiftEqual(existing, item))) output.push(item);
    }
    return output;
  }
  """

  @spec compile_module(module()) :: String.t()
  def compile_module(module) do
    {entries, template} = compile_parts(module)

    "// Generated by LiveLift. Do not edit.\n" <>
      @helpers <>
      "export const actions = {\n" <>
      Enum.map_join(entries, ",\n", &("  " <> &1)) <>
      "\n};\n" <>
      if(is_list(template),
        do: "export const template = #{Jason.encode!(template)};\n",
        else: ""
      )
  end

  @spec compile_registry([module()]) :: String.t()
  def compile_registry(modules) do
    entries =
      modules
      |> expand_components()
      |> Enum.sort()
      |> Enum.map(fn module ->
        {actions, template} = compile_parts(module)

        unless is_list(template) do
          raise ArgumentError, "#{inspect(module)} has no client_template"
        end

        name = module |> Atom.to_string() |> String.replace_prefix("Elixir.", "")

        "  #{Jason.encode!(name)}: {actions: {#{Enum.join(actions, ", ")}}, " <>
          "template: #{Jason.encode!(template)}, component: #{function_exported?(module, :__live_lift_component__, 0)}}"
      end)

    "// Generated by LiveLift. Do not edit.\n" <>
      @helpers <>
      "export const views = {\n" <>
      Enum.join(entries, ",\n") <> "\n};\n"
  end

  @doc "Returns the registry and a source map pointing each view entry to its Elixir template."
  def compile_registry_with_map(modules, output_name) do
    expanded = modules |> expand_components() |> Enum.sort()
    javascript = compile_registry(expanded)

    sources =
      Enum.map(expanded, fn module ->
        {file, line} = module.__live_lift_template_source__()
        {Path.relative_to_cwd(file), line, File.read!(file)}
      end)

    mappings =
      javascript
      |> String.split("\n")
      |> Enum.map_reduce({0, 0}, fn generated_line, {previous_source, previous_line} ->
        index =
          Enum.find_index(expanded, fn module ->
            name = module |> Atom.to_string() |> String.replace_prefix("Elixir.", "")
            String.contains?(generated_line, "#{Jason.encode!(name)}: {actions:")
          end)

        if index == nil do
          {"", {previous_source, previous_line}}
        else
          {_file, line, _content} = Enum.at(sources, index)
          original_line = line - 1

          segment =
            [2, index - previous_source, original_line - previous_line, 0]
            |> Enum.map_join(&vlq/1)

          {segment, {index, original_line}}
        end
      end)
      |> elem(0)
      |> Enum.join(";")

    map = %{
      version: 3,
      file: Path.basename(output_name),
      sources: Enum.map(sources, &elem(&1, 0)),
      sourcesContent: Enum.map(sources, &elem(&1, 2)),
      names: [],
      mappings: mappings
    }

    {javascript, Jason.encode!(map)}
  end

  defp vlq(value) do
    encoded = if value < 0, do: -value * 2 + 1, else: value * 2
    vlq_digits(encoded, "")
  end

  defp vlq_digits(value, output) do
    digit = Bitwise.band(value, 31)
    rest = Bitwise.bsr(value, 5)
    digit = if rest > 0, do: Bitwise.bor(digit, 32), else: digit

    output =
      output <>
        String.at("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/", digit)

    if rest > 0, do: vlq_digits(rest, output), else: output
  end

  @spec compile_action(atom(), atom(), Macro.t()) :: String.t()
  def compile_action(name, arg, body) when is_atom(name) and is_atom(arg) do
    name_string = identifier!(name)
    arg_string = identifier!(arg)
    expression = compile_expr(body, arg)

    "#{name_string}: (#{arg_string}) => #{expression}"
  end

  def compile_action(name, [state, event], body)
      when is_atom(name) and is_atom(state) and is_atom(event) do
    name_string = identifier!(name)
    state_string = identifier!(state)
    event_string = identifier!(event)
    expression = compile_expr(body, [state, event])
    "#{name_string}: (#{state_string}, #{event_string}) => #{expression}"
  end

  defp compile_expr(value, _arg) when is_integer(value) and abs(value) <= @max_safe_integer,
    do: Integer.to_string(value)

  defp compile_expr(value, _arg) when is_float(value),
    do: "__liveLiftFloat(#{Float.to_string(value)})"

  defp compile_expr(value, _arg) when is_binary(value) or is_boolean(value) or is_nil(value),
    do: Jason.encode!(value)

  defp compile_expr({name, _, context}, arg)
       when name == arg and (is_atom(context) or is_nil(context)),
       do: Atom.to_string(arg)

  defp compile_expr({name, _, context}, args)
       when is_list(args) and is_atom(name) and (is_atom(context) or is_nil(context)) do
    if name in args,
      do: Atom.to_string(name),
      else: raise(ArgumentError, "unsupported client variable: #{name}")
  end

  defp compile_expr({{:., _, [source, key]}, _, []}, arg) when is_atom(key) do
    "__liveLiftGet(#{compile_expr(source, arg)}, #{Jason.encode!(identifier!(key))})"
  end

  defp compile_expr({:%{}, _, [{:|, _, [map, fields]}]}, arg) when is_list(fields) do
    entries =
      Enum.map(fields, fn
        {key, value} when is_atom(key) ->
          "#{identifier!(key)}: #{compile_expr(value, arg)}"

        other ->
          raise ArgumentError, "unsupported client map update: #{Macro.to_string(other)}"
      end)

    "__liveLiftMapUpdate(#{compile_expr(map, arg)}, {#{Enum.join(entries, ", ")}})"
  end

  defp compile_expr({:__live_lift_assign_new__, _, [map, field, fallback]}, arg)
       when is_atom(field) do
    "__liveLiftAssignNew(#{compile_expr(map, arg)}, #{Jason.encode!(identifier!(field))}, () => #{compile_expr(fallback, arg)})"
  end

  defp compile_expr({:%{}, _, fields}, arg) when is_list(fields) do
    entries =
      Enum.map(fields, fn
        {key, value} when is_atom(key) ->
          "#{identifier!(key)}: #{compile_expr(value, arg)}"

        other ->
          raise ArgumentError, "unsupported client map field: #{Macro.to_string(other)}"
      end)

    "({#{Enum.join(entries, ", ")}})"
  end

  defp compile_expr({op, _, [left, right]}, arg) when op in [:+, :-, :*] do
    "__liveLiftArithmetic(#{compile_expr(left, arg)}, #{compile_expr(right, arg)}, #{Jason.encode!(Atom.to_string(op))})"
  end

  defp compile_expr({:rem, _, [left, right]}, arg),
    do: "__liveLiftRem(#{compile_expr(left, arg)}, #{compile_expr(right, arg)})"

  defp compile_expr({:<>, _, [left, right]}, arg),
    do:
      "(__liveLiftString(#{compile_expr(left, arg)}) + __liveLiftString(#{compile_expr(right, arg)}))"

  defp compile_expr({op, _, [left, right]}, arg) when op in [:<, :<=, :>, :>=] do
    "(__liveLiftNumber(#{compile_expr(left, arg)}) #{op} __liveLiftNumber(#{compile_expr(right, arg)}))"
  end

  defp compile_expr({op, _, [left, right]}, arg) when op in [:&&, :||] do
    helper = if op == :&&, do: "__liveLiftAnd", else: "__liveLiftOr"
    "#{helper}(#{compile_expr(left, arg)}, () => #{compile_expr(right, arg)})"
  end

  defp compile_expr({op, _, [value]}, arg) when op in [:+, :-] do
    "__liveLiftUnary(#{compile_expr(value, arg)}, #{Jason.encode!(Atom.to_string(op))})"
  end

  defp compile_expr({:!, _, [value]}, arg), do: "(!__liveLiftTruthy(#{compile_expr(value, arg)}))"

  defp compile_expr({:++, _, [left, right]}, arg) do
    "__liveLiftList(#{compile_expr(left, arg)}).concat(__liveLiftList(#{compile_expr(right, arg)}))"
  end

  defp compile_expr({:length, _, [value]}, arg),
    do: "__liveLiftList(#{compile_expr(value, arg)}).length"

  defp compile_expr({{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, [list]}, arg),
    do: "[...__liveLiftList(#{compile_expr(list, arg)})].reverse()"

  defp compile_expr({{:., _, [{:__aliases__, _, [:Map]}, :put]}, _, [map, key, value]}, arg)
       when is_atom(key) do
    "__liveLiftMapPut(#{compile_expr(map, arg)}, #{Jason.encode!(identifier!(key))}, #{compile_expr(value, arg)})"
  end

  defp compile_expr({{:., _, [{:__aliases__, _, [:Map]}, :get]}, _, [map, key]}, arg)
       when is_atom(key) do
    "__liveLiftMapGet(#{compile_expr(map, arg)}, #{Jason.encode!(identifier!(key))}, null)"
  end

  defp compile_expr({{:., _, [{:__aliases__, _, [:Map]}, :get]}, _, [map, key, fallback]}, arg)
       when is_atom(key) do
    "__liveLiftMapGet(#{compile_expr(map, arg)}, #{Jason.encode!(identifier!(key))}, #{compile_expr(fallback, arg)})"
  end

  defp compile_expr({{:., _, [{:__aliases__, _, [:Map]}, :merge]}, _, [left, right]}, arg) do
    "__liveLiftMapMerge(#{compile_expr(left, arg)}, #{compile_expr(right, arg)})"
  end

  defp compile_expr({{:., _, [{:__aliases__, _, [:Map]}, :delete]}, _, [map, key]}, arg)
       when is_atom(key) do
    "__liveLiftMapDelete(#{compile_expr(map, arg)}, #{Jason.encode!(identifier!(key))})"
  end

  defp compile_expr({{:., _, [{:__aliases__, _, [:Map]}, :take]}, _, [map, keys]}, arg)
       when is_list(keys) do
    if Enum.all?(keys, &is_atom/1) do
      names = Enum.map(keys, &identifier!/1)
      "__liveLiftMapTake(#{compile_expr(map, arg)}, #{Jason.encode!(names)})"
    else
      raise ArgumentError,
            "unsupported client Map.take/2 keys: use a literal list of atom keys or move this handler to the server"
    end
  end

  defp compile_expr({{:., _, [{:__aliases__, _, [:Map]}, :take]}, _, [_map, _keys]}, _arg) do
    raise ArgumentError,
          "unsupported client Map.take/2 keys: use a literal list of atom keys or move this handler to the server"
  end

  defp compile_expr(
         {{:., _, [{:__aliases__, _, [:Enum]}, operation]}, _,
          [list, {:fn, _, [{:->, _, [[{variable, _, context}], body]}]}]},
         args
       )
       when operation in [:map, :filter, :reject, :any?, :all?] and is_atom(variable) and
              (is_atom(context) or is_nil(context)) do
    variable_name = identifier!(variable)
    callback = compile_expr(body, List.wrap(args) ++ [variable])

    method =
      case operation do
        :map -> "map"
        :any? -> "some"
        :all? -> "every"
        _ -> "filter"
      end

    result =
      case operation do
        :map -> callback
        :reject -> "!__liveLiftTruthy(#{callback})"
        _ -> "__liveLiftTruthy(#{callback})"
      end

    "__liveLiftList(#{compile_expr(list, args)}).#{method}((#{variable_name}) => #{result})"
  end

  defp compile_expr({{:., _, [{:__aliases__, _, [:Enum]}, :member?]}, _, [list, value]}, arg) do
    "__liveLiftMember(#{compile_expr(list, arg)}, #{compile_expr(value, arg)})"
  end

  defp compile_expr(
         {{:., _, [{:__aliases__, _, [:Enum]}, :find]}, _,
          [list, {:fn, _, [{:->, _, [[{variable, _, context}], body]}]}]},
         args
       )
       when is_atom(variable) and (is_atom(context) or is_nil(context)) do
    compile_find(list, nil, variable, body, args)
  end

  defp compile_expr(
         {{:., _, [{:__aliases__, _, [:Enum]}, :find]}, _,
          [list, fallback, {:fn, _, [{:->, _, [[{variable, _, context}], body]}]}]},
         args
       )
       when is_atom(variable) and (is_atom(context) or is_nil(context)) do
    compile_find(list, fallback, variable, body, args)
  end

  defp compile_expr(
         {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _,
          [list, {:fn, _, [{:->, _, [[{item, _, item_context}, {acc, _, acc_context}], body]}]}]},
         args
       )
       when is_atom(item) and is_atom(acc) and item != acc and
              (is_atom(item_context) or is_nil(item_context)) and
              (is_atom(acc_context) or is_nil(acc_context)) do
    compile_reduce(list, nil, body, item, acc, args, false)
  end

  defp compile_expr(
         {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _,
          [
            list,
            initial,
            {:fn, _, [{:->, _, [[{item, _, item_context}, {acc, _, acc_context}], body]}]}
          ]},
         args
       )
       when is_atom(item) and is_atom(acc) and item != acc and
              (is_atom(item_context) or is_nil(item_context)) and
              (is_atom(acc_context) or is_nil(acc_context)) do
    compile_reduce(list, initial, body, item, acc, args, true)
  end

  defp compile_expr(
         {{:., _, [{:__aliases__, _, [:Enum]}, :sort_by]}, _,
          [list, {:fn, _, [{:->, _, [[{variable, _, context}], body]}]}]},
         args
       )
       when is_atom(variable) and (is_atom(context) or is_nil(context)) do
    name = identifier!(variable)
    key = compile_expr(body, List.wrap(args) ++ [variable])
    "__liveLiftSortBy(#{compile_expr(list, args)}, (#{name}) => #{key})"
  end

  defp compile_expr({{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, [list]}, args) do
    "__liveLiftList(#{compile_expr(list, args)}).length"
  end

  defp compile_expr(
         {{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _,
          [list, {:fn, _, [{:->, _, [[{variable, _, context}], body]}]}]},
         args
       )
       when is_atom(variable) and (is_atom(context) or is_nil(context)) do
    name = identifier!(variable)
    predicate = compile_expr(body, List.wrap(args) ++ [variable])
    "__liveLiftCount(#{compile_expr(list, args)}, (#{name}) => #{predicate})"
  end

  defp compile_expr({{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, [list]}, args) do
    "__liveLiftJoin(#{compile_expr(list, args)}, \"\")"
  end

  defp compile_expr({{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, [list, separator]}, args) do
    "__liveLiftJoin(#{compile_expr(list, args)}, #{compile_expr(separator, args)})"
  end

  defp compile_expr({{:., _, [{:__aliases__, _, [:Enum]}, operation]}, _, [list, count]}, arg)
       when operation in [:take, :drop] do
    helper = if operation == :take, do: "__liveLiftTake", else: "__liveLiftDrop"
    "#{helper}(#{compile_expr(list, arg)}, #{compile_expr(count, arg)})"
  end

  defp compile_expr({{:., _, [{:__aliases__, _, [:Enum]}, :uniq]}, _, [list]}, arg) do
    "__liveLiftUniq(#{compile_expr(list, arg)})"
  end

  defp compile_expr(
         {{:., _, [{:__aliases__, _, [:String]}, :contains?]}, _, [text, patterns]},
         arg
       ) do
    "__liveLiftContains(#{compile_expr(text, arg)}, #{compile_expr(patterns, arg)})"
  end

  defp compile_expr({{:., _, [{:__aliases__, _, [:String]}, :trim]}, _, [text]}, arg) do
    "__liveLiftTrim(#{compile_expr(text, arg)})"
  end

  defp compile_expr({{:., _, [{:__aliases__, _, [:String]}, :length]}, _, [text]}, arg) do
    "__liveLiftStringLength(#{compile_expr(text, arg)})"
  end

  defp compile_expr({{:., _, [{:__aliases__, _, [:Integer]}, :to_string]}, _, [value]}, arg) do
    "String(__liveLiftInt(#{compile_expr(value, arg)}))"
  end

  defp compile_expr({:if, _, [condition, branches]}, arg) when is_list(branches) do
    then_expr =
      case Keyword.fetch(branches, :do) do
        {:ok, expression} -> expression
        :error -> raise ArgumentError, "unsupported client if: missing do branch"
      end

    else_expr = Keyword.get(branches, :else)
    test = compile_expr(condition, arg)

    "(__liveLiftTruthy(#{test}) ? #{compile_expr(then_expr, arg)} : #{compile_expr(else_expr, arg)})"
  end

  defp compile_expr({:cond, _, [[do: clauses]]}, arg) when is_list(clauses) and clauses != [] do
    Enum.reduce(Enum.reverse(clauses), "__liveLiftCondFailure()", fn
      {:->, _, [[condition], result]}, fallback ->
        "(__liveLiftTruthy(#{compile_expr(condition, arg)}) ? #{compile_expr(result, arg)} : #{fallback})"

      other, _fallback ->
        raise ArgumentError,
              "unsupported client cond clause: #{Macro.to_string(other)}; use one condition per clause"
    end)
  end

  defp compile_expr({:cond, _, _}, _arg) do
    raise ArgumentError,
          "unsupported client cond: use a nonempty do block with one condition per clause"
  end

  defp compile_expr({:|>, _, [source, {callee, metadata, arguments}]}, args)
       when is_list(arguments) do
    compile_expr({callee, metadata, [source | arguments]}, args)
  end

  defp compile_expr({:|>, _, _}, _args) do
    raise ArgumentError,
          "unsupported client pipe target: use a supported function call or move this handler to the server"
  end

  defp compile_expr({:case, _, [value, [do: clauses]]}, args)
       when is_list(clauses) and clauses != [] do
    branches =
      Enum.map(clauses, fn
        {:->, _, [[{:when, _, _}], _result]} ->
          raise ArgumentError,
                "unsupported client case guard; use an unguarded pattern or move this handler to the server"

        {:->, _, [[pattern], result]} ->
          {descriptor, names} = compile_case_pattern(pattern)
          inputs = Enum.map_join(names, ", ", &"$liveLiftCaseBindings[#{Jason.encode!(&1)}]")
          parameters = Enum.join(names, ", ")

          "if (__liveLiftMatch($liveLiftCaseValue, #{Jason.encode!(descriptor)}, " <>
            "($liveLiftCaseBindings = Object.create(null)))) { " <>
            "return ((#{parameters}) => #{compile_expr(result, List.wrap(args) ++ Enum.map(names, &String.to_atom/1))})(#{inputs}); }"

        other ->
          raise ArgumentError,
                "unsupported client case clause: #{Macro.to_string(other)}; use one unguarded pattern per clause"
      end)

    "(($liveLiftCaseValue) => { let $liveLiftCaseBindings; " <>
      "#{Enum.join(branches, " ")} return __liveLiftCaseFailure(); })(#{compile_expr(value, args)})"
  end

  defp compile_expr({:case, _, _}, _args) do
    raise ArgumentError,
          "unsupported client case: use a nonempty do block with unguarded patterns"
  end

  defp compile_expr({:__live_lift_helper_failure__, _, [name]}, _args) when is_binary(name),
    do: "__liveLiftHelperFailure(#{Jason.encode!(name)})"

  defp compile_expr({op, _, [left, right]}, arg) when op in [:==, :!=] do
    comparison = "__liveLiftEqual(#{compile_expr(left, arg)}, #{compile_expr(right, arg)})"
    if op == :==, do: comparison, else: "(!#{comparison})"
  end

  defp compile_expr(values, arg) when is_list(values) do
    "[#{Enum.map_join(values, ", ", &compile_expr(&1, arg))}]"
  end

  defp compile_expr(other, _arg) do
    raise ArgumentError, "unsupported client expression: #{Macro.to_string(other)}"
  end

  defp compile_find(list, fallback, variable, body, args) do
    name = identifier!(variable)
    predicate = compile_expr(body, List.wrap(args) ++ [variable])

    "__liveLiftFind(#{compile_expr(list, args)}, #{compile_expr(fallback, args)}, (#{name}) => #{predicate})"
  end

  defp compile_reduce(list, initial, body, item, acc, args, seeded) do
    item_name = identifier!(item)
    acc_name = identifier!(acc)
    expression = compile_expr(body, List.wrap(args) ++ [item, acc])

    "__liveLiftReduce(#{compile_expr(list, args)}, #{compile_expr(initial, args)}, " <>
      "(#{item_name}, #{acc_name}) => #{expression}, #{seeded})"
  end

  defp compile_case_pattern(pattern) do
    {descriptor, names} = case_pattern(pattern)

    if length(names) != length(Enum.uniq(names)) do
      raise ArgumentError,
            "unsupported client case pattern: bind each variable once; use ^ for matching an existing value on the server"
    end

    {descriptor, names}
  end

  defp case_pattern(value)
       when (is_integer(value) and abs(value) <= @max_safe_integer) or is_float(value) or
              is_binary(value) or is_boolean(value) or is_nil(value),
       do: {%{type: "literal", value: LiveLift.FloatWire.encode(value)}, []}

  defp case_pattern({operation, _, [value]})
       when operation in [:+, :-] and is_number(value) do
    signed = if operation == :-, do: -value, else: +value
    case_pattern(signed)
  end

  defp case_pattern({:_, _, context}) when is_atom(context) or is_nil(context),
    do: {%{type: "wildcard"}, []}

  defp case_pattern({:=, _, [left, right]}) do
    {left_pattern, left_names} = case_pattern(left)
    {right_pattern, right_names} = case_pattern(right)
    {%{type: "alias", left: left_pattern, right: right_pattern}, left_names ++ right_names}
  end

  defp case_pattern({name, _, context})
       when is_atom(name) and (is_atom(context) or is_nil(context)) do
    identifier!(name)
    {%{type: "variable", name: Atom.to_string(name)}, [Atom.to_string(name)]}
  end

  defp case_pattern({:%{}, _, fields}) when is_list(fields) do
    {entries, names} =
      Enum.map_reduce(fields, [], fn
        {key, value}, acc when is_atom(key) ->
          key = Atom.to_string(key)
          safe_case_key!(key)
          {descriptor, bound} = case_pattern(value)
          {[key, descriptor], acc ++ bound}

        other, _acc ->
          raise ArgumentError,
                "unsupported client case map pattern: #{Macro.to_string(other)}; use safe atom keys"
      end)

    if length(entries) != length(Enum.uniq_by(entries, &hd/1)) do
      raise ArgumentError, "unsupported client case map pattern: duplicate key"
    end

    {%{type: "map", entries: entries}, names}
  end

  defp case_pattern(values) when is_list(values) do
    case List.last(values) do
      {:|, _, [head, tail]} ->
        prefix = Enum.drop(values, -1) ++ [head]
        {tail_pattern, tail_names} = case_pattern(tail)

        Enum.reduce(Enum.reverse(prefix), {tail_pattern, tail_names}, fn item, {rest, names} ->
          {head_pattern, head_names} = case_pattern(item)
          {%{type: "cons", head: head_pattern, tail: rest}, head_names ++ names}
        end)

      _ ->
        {items, names} =
          Enum.map_reduce(values, [], fn item, acc ->
            {descriptor, bound} = case_pattern(item)
            {descriptor, acc ++ bound}
          end)

        {%{type: "list", items: items}, names}
    end
  end

  defp case_pattern(other) do
    raise ArgumentError,
          "unsupported client case pattern: #{Macro.to_string(other)}; use literals, lists, maps, variables or _"
  end

  defp safe_case_key!(key) do
    unless Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, key) and
             key not in @reserved do
      raise ArgumentError, "unsupported client case map key: #{inspect(key)}"
    end
  end

  defp identifier!(name) do
    identifier = Atom.to_string(name)

    if Regex.match?(@identifier, identifier) and identifier not in @reserved do
      identifier
    else
      raise ArgumentError, "unsupported client identifier: #{identifier}"
    end
  end

  defp compile_parts(module) do
    unless function_exported?(module, :__live_lift_client_actions__, 0) do
      raise ArgumentError, "#{inspect(module)} has no LiveLift client actions"
    end

    actions = module.__live_lift_client_actions__()
    entries = Enum.map(actions, fn {name, arg, body} -> compile_action(name, arg, body) end)
    template = module.__live_lift_client_template__()

    if is_list(template) do
      known_actions = MapSet.new(actions, fn {name, _, _} -> Atom.to_string(name) end)

      for action_name <- template_actions(template),
          not function_exported?(module, :__live_lift_component__, 0),
          not MapSet.member?(known_actions, action_name) do
        raise ArgumentError, "unknown client template action: #{action_name}"
      end
    end

    {entries, template}
  end

  defp template_actions(nodes, visited \\ MapSet.new()) do
    Enum.flat_map(nodes, fn
      %{type: "element", attrs: attrs, children: children} ->
        actions =
          for %{name: name, value: value} <- attrs,
              name in ~w(data-live-lift-action data-live-lift-input data-live-lift-change data-live-lift-submit),
              do: value

        actions ++ template_actions(children, visited)

      %{type: "component", module: name} ->
        module = component_module!(name)

        if MapSet.member?(visited, module) do
          raise ArgumentError, "recursive LiveLift client component: #{name}"
        end

        template_actions(module.__live_lift_client_template__(), MapSet.put(visited, module))

      _ ->
        []
    end)
  end

  defp expand_components(modules) do
    Enum.reduce(modules, MapSet.new(), &collect_components(&1, &2)) |> MapSet.to_list()
  end

  defp collect_components(module, seen) do
    if MapSet.member?(seen, module) do
      seen
    else
      seen = MapSet.put(seen, module)
      template = module.__live_lift_client_template__()

      unless is_list(template),
        do: raise(ArgumentError, "#{inspect(module)} has no client_template")

      template
      |> component_names()
      |> Enum.reduce(seen, fn name, acc -> collect_components(component_module!(name), acc) end)
    end
  end

  defp component_names(nodes) do
    Enum.flat_map(nodes, fn
      %{type: "component", module: name} -> [name]
      %{type: "element", children: children} -> component_names(children)
      _ -> []
    end)
  end

  defp component_module!(name) do
    module = Module.concat(String.split(name, "."))

    unless Code.ensure_loaded?(module) and
             function_exported?(module, :__live_lift_component__, 0) and
             function_exported?(module, :__live_lift_client_template__, 0) do
      raise ArgumentError, "unknown LiveLift client component: #{name}"
    end

    module
  end
end
