defmodule ExileTest do
  use ExUnit.Case

  doctest Exile

  test "stream with enumerable" do
    proc_stream =
      Exile.stream!(["cat"], input: Stream.map(1..1000, fn _ -> "a" end), enable_stderr: false)

    stdout = proc_stream |> Enum.to_list()
    assert IO.iodata_length(stdout) == 1000
  end

  test "stream with collectable" do
    proc_stream =
      Exile.stream!(["cat"], input: fn sink -> Enum.into(1..1000, sink, fn _ -> "a" end) end)

    stdout = Enum.to_list(proc_stream)
    assert IO.iodata_length(stdout) == 1000
  end

  test "stream without stdin" do
    proc_stream = Exile.stream!(~w(echo hello))
    stdout = Enum.to_list(proc_stream)
    assert IO.iodata_to_binary(stdout) == "hello\n"
  end

  test "stderr" do
    proc_stream = Exile.stream!(["sh", "-c", "echo foo >>/dev/stderr"], enable_stderr: true)

    assert {[], stderr} = split_stream(proc_stream)
    assert IO.iodata_to_binary(stderr) == "foo\n"
  end

  test "multiple streams" do
    script = """
    for i in {1..1000}; do
      echo "foo ${i}"
      echo "bar ${i}" >&2
    done
    """

    proc_stream = Exile.stream!(["sh", "-c", script], enable_stderr: true)

    {stdout, stderr} = split_stream(proc_stream)

    stdout_lines = String.split(Enum.join(stdout), "\n", trim: true)
    stderr_lines = String.split(Enum.join(stderr), "\n", trim: true)

    assert length(stdout_lines) == length(stderr_lines)
    assert Enum.all?(stdout_lines, &String.starts_with?(&1, "foo "))
    assert Enum.all?(stderr_lines, &String.starts_with?(&1, "bar "))
  end

  test "environment variable" do
    output =
      Exile.stream!(~w(printenv FOO), env: %{"FOO" => "bar"})
      |> Enum.to_list()
      |> IO.iodata_to_binary()

    assert output == "bar\n"
  end

  test "premature stream termination" do
    input_stream = Stream.map(1..100_000, fn _ -> "hello" end)

    assert_raise Exile.Process.Error,
                 "abnormal command exit, received EPIPE while writing to stdin",
                 fn ->
                   Exile.stream!(~w(cat), input: input_stream)
                   |> Enum.take(1)
                 end
  end

  test "premature stream termination when ignore_epipe is true" do
    input_stream = Stream.map(1..100_000, fn _ -> "hello" end)

    assert ["hello"] ==
             Exile.stream!(~w(cat), input: input_stream, ignore_epipe: true, max_chunk_size: 5)
             |> Enum.take(1)
  end

  defp split_stream(stream) do
    {stdout, stderr} =
      Enum.reduce(stream, {[], []}, fn
        {:stdout, data}, {stdout, stderr} -> {[data | stdout], stderr}
        {:stderr, data}, {stdout, stderr} -> {stdout, [data | stderr]}
      end)

    {Enum.reverse(stdout), Enum.reverse(stderr)}
  end
end
