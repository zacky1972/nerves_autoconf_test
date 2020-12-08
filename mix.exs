defmodule NervesAutoconfTest.MixProject do
  use Mix.Project

  @app :nerves_autoconf_test
  @version "0.1.0"
  @all_targets [:rpi, :rpi0, :rpi2, :rpi3, :rpi3a, :rpi4, :bbb, :osd32mp1, :x86_64]

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.9",
      archives: [nerves_bootstrap: "~> 1.10"],
      start_permanent: Mix.env() == :prod,
      build_embedded: true,
      deps: deps(),
      releases: [{@app, release()}],
      preferred_cli_target: [run: :host, test: :host],
      compilers: [:elixir_make] ++ Mix.compilers(),
      aliases: [
        compile: [&autoreconf/1, &configure/1, "clean", "compile", &install/1],
        clean: [&autoreconf/1, &configure/1, "clean"]
      ],
      make_clean: ["clean"]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {NervesAutoconfTest.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Dependencies for all targets
      {:nerves, "~> 1.7.0", runtime: false},
      {:shoehorn, "~> 0.7.0"},
      {:ring_logger, "~> 0.8.1"},
      {:toolshed, "~> 0.2.13"},
      {:elixir_make, "~> 0.6.2", runtime: false},

      # Dependencies for all targets except :host
      {:nerves_runtime, "~> 0.11.3", targets: @all_targets},
      {:nerves_pack, "~> 0.4.0", targets: @all_targets},

      # Dependencies for specific targets
      {:nerves_system_rpi, "~> 1.13", runtime: false, targets: :rpi},
      {:nerves_system_rpi0, "~> 1.13", runtime: false, targets: :rpi0},
      {:nerves_system_rpi2, "~> 1.13", runtime: false, targets: :rpi2},
      {:nerves_system_rpi3, "~> 1.13", runtime: false, targets: :rpi3},
      {:nerves_system_rpi3a, "~> 1.13", runtime: false, targets: :rpi3a},
      {:nerves_system_rpi4, "~> 1.13", runtime: false, targets: :rpi4},
      {:nerves_system_bbb, "~> 2.8", runtime: false, targets: :bbb},
      {:nerves_system_osd32mp1, "~> 0.4", runtime: false, targets: :osd32mp1},
      {:nerves_system_x86_64, "~> 1.13", runtime: false, targets: :x86_64}
    ]
  end

  def release do
    [
      overwrite: true,
      cookie: "#{@app}_cookie",
      include_erts: &Nerves.Release.erts/0,
      steps: [&Nerves.Release.init/1, :assemble],
      strip_beams: Mix.env() == :prod
    ]
  end

  defp autoreconf(_args) do
    System.cmd("autoreconf", ["-i"])
  end

  defp configure(_args) do
    arch = get_arch(System.get_env("REBAR_TARGET_ARCH"))

    System.cmd(
      "#{File.cwd!()}/configure",
      ["--prefix=#{Mix.Project.app_path()}/priv", "--host=#{arch}", "--target=#{arch}"]
    )
  end

  defp get_arch(nil) do
    lib_dir =
      System.get_env(
        "ERL_EI_LIBDIR",
        :code.root_dir() |> to_string() |> Kernel.<>("/usr/lib")
      )

    System.cmd("ar", ["-xv", "#{lib_dir}/libei.a", "ei_compat.o"])

    {uname_m, 0} = System.cmd("uname", ["-m"])
    {uname_s, 0} = System.cmd("uname", ["-s"])
    {uname_r, 0} = System.cmd("uname", ["-r"])

    r =
      case System.cmd("file", ["ei_compat.o"]) do
        {result, 0} ->
          l = String.split(result)

          arch =
            Enum.filter(
              %{
                "x86_64" => l |> Enum.filter(&String.match?(&1, ~r/x86.64/)) |> length,
                "arm64" => l |> Enum.filter(&String.match?(&1, ~r/arm64/)) |> length,
                "aarch64" => l |> Enum.filter(&String.match?(&1, ~r/aarch64/)) |> length
              },
              fn {_, v} -> v != 0 end
            )

          platform =
            Enum.filter(
              %{
                "apple-darwin#{uname_r}" =>
                  l |> Enum.filter(&String.match?(&1, ~r/Mach-O/)) |> length,
                "linux-gnu" => l |> Enum.filter(&String.match?(&1, ~r/ELF/)) |> length
              },
              fn {_, v} -> v != 0 end
            )

          "#{arch |> hd() |> elem(0)}-#{platform |> hd() |> elem(0)}"

        _ ->
          platform =
            case uname_s do
              "Linux" -> "linux-gnu"
              "Darwin" -> "apple-darwin#{uname_r}"
              _ -> raise "unsupported platform"
            end

          "#{uname_m}-#{platform}"
      end

    File.rm("ei_compat.o")
    r
  end

  defp get_arch(arch), do: arch

  defp install(_args) do
    System.cmd("make", ["install"])
  end
end
