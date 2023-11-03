defmodule Mix.Tasks.GenDSL.Plugin do
  use Mix.Task
  import Mix.Generator

  @shortdoc "Creates a new Elixir project"

  @moduledoc """
  Creates a new Elixir project.
  It expects the path of the project as argument.

      $ mix new PATH [--app APP] [--module MODULE] [--sup] [--umbrella]

  A project at the given PATH will be created. The
  application name and module name will be retrieved
  from the path, unless `--module` or `--app` is given.

  An `--app` option can be given in order to
  name the OTP application for the project.

  A `--module` option can be given in order
  to name the modules in the generated code skeleton.

  A `--sup` option can be given to generate an OTP application
  skeleton including a supervision tree. Normally an app is
  generated without a supervisor and without the app callback.

  An `--umbrella` option can be given to generate an
  umbrella project.

  ## Examples

      $ mix new hello_world

  Is equivalent to:

      $ mix new hello_world --module HelloWorld

  To generate an app with a supervision tree and an application callback:

      $ mix new hello_world --sup

  To generate an umbrella application with sub applications:

      $ mix new hello_world --umbrella
      $ cd hello_world/apps
      $ mix new child_app

  """

  @switches [
    app: :string,
    module: :string,
  ]

  @impl true
  def run(argv) do
    {opts, argv} = OptionParser.parse!(argv, strict: @switches)

    case argv do
      [] ->
        Mix.raise("Expected PATH to be given, please use \"mix new PATH\"")

      [path | _] ->
        app = opts[:app] || Path.basename(Path.expand(path))
        check_application_name!(app, !opts[:app])
        mod = opts[:module] || Macro.camelize(app)
        check_mod_name_validity!(mod)
        check_mod_name_availability!(mod)

        unless path == "." do
          check_directory_existence!(path)
          File.mkdir_p!(path)
        end

        File.cd!(path, fn ->
            generate(app, mod, path, opts)
        end)
    end
  end

  defp generate(app, mod, path, _opts) do
    assigns = [
      app: app,
      mod: mod,
      version: get_version(System.version())
    ]

    mod_filename = Macro.underscore(mod)

    create_file("README.md", readme_template(assigns))
    create_file(".formatter.exs", formatter_template(assigns))
    create_file(".gitignore", gitignore_template(assigns))

    create_file("mix.exs", mix_exs_template(assigns))

    create_directory("lib")
    create_file("lib/#{mod_filename}.ex", lib_template(assigns))


    create_directory("test")
    create_file("test/test_helper.exs", test_helper_template(assigns))
    create_file("test/#{mod_filename}_test.exs", test_template(assigns))

    """

    Your Mix project was created successfully.
    You can use "mix" to compile it, test it, and more:

        #{cd_path(path)}mix test

    Run "mix help" for more commands.
    """
    |> String.trim_trailing()
    |> Mix.shell().info()
  end

  @doc """
  Returns a list of reserved application names.
  """
  def reserved_application_names do
    # 1. Command line flags with multiple args can conflict with application names
    # 2. OTP names
    # 3. Elixir names
    ~w(boot_var compile config configfd env pa pz path run s setcookie)a ++
      ~w(otp asn1 common_test compiler crypto debugger dialyzer diameter
         edoc eldap erl_docgen erl_interface erts et eunit ftp hipe
         inets jinterface kernel megaco mnesia observer odbc os_mon
         parsetools public_key reltool runtime_tools sasl snmp ssh
         ssl stdlib syntax_tools toolbar tools typer wx xmerl)a ++
      ~w(eex elixir ex_unit iex logger mix)a
  end


  defp cd_path("."), do: ""
  defp cd_path(path), do: "cd #{path}\n    "

  defp check_application_name!(name, inferred?) do
    if message = invalid_app(name) || reserved_app(name) do
      Mix.raise(
        message <>
          if inferred? do
            ". The application name is inferred from the path, if you'd like to " <>
              "explicitly name the application then use the \"--app APP\" option"
          else
            ""
          end
      )
    end
  end

  defp invalid_app(name) do
    unless name =~ ~r/^[a-z][a-z0-9_]*$/ do
      "Application name must start with a lowercase ASCII letter, followed by " <>
        "lowercase ASCII letters, numbers, or underscores, got: #{inspect(name)}"
    end
  end

  defp reserved_app(name) do
    atom_name = String.to_atom(name)

    if atom_name in reserved_application_names() or Application.ensure_loaded(atom_name) == :ok do
      "Cannot use application name #{inspect(name)} because it is already used by Erlang/OTP or Elixir"
    end
  end

  defp check_mod_name_validity!(name) do
    unless name =~ ~r/^[A-Z]\w*(\.[A-Z]\w*)*$/ do
      Mix.raise(
        "Module name must be a valid Elixir alias (for example: Foo.Bar), got: #{inspect(name)}"
      )
    end
  end

  defp check_mod_name_availability!(name) do
    name = Module.concat(Elixir, name)

    if Code.ensure_loaded?(name) do
      Mix.raise("Module name #{inspect(name)} is already taken, please choose another name")
    end
  end

  defp check_directory_existence!(path) do
    msg = "The directory #{inspect(path)} already exists. Are you sure you want to continue?"

    if File.dir?(path) and not Mix.shell().yes?(msg) do
      Mix.raise("Please select another directory for installation")
    end
  end

  defp get_version(version) do
    {:ok, version} = Version.parse(version)

    "#{version.major}.#{version.minor}" <>
      case version.pre do
        [h | _] -> "-#{h}"
        [] -> ""
      end
  end



  embed_template(:readme, """
  # <%= @mod %>

  **TODO: Add description**
  <%= if @app do %>
  ## Installation

  If [available in Hex](https://hex.pm/docs/publish), the package can be installed
  by adding `<%= @app %>` to your list of dependencies in `mix.exs`:

  ```elixir
  def deps do
    [
      {:<%= @app %>, "~> 0.1.0"}
    ]
  end
  ```

  Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
  and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
  be found at <https://hexdocs.pm/<%= @app %>>.
  <% end %>
  """)

  embed_template(:formatter, """
  # Used by "mix format"
  [
    inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
  ]
  """)

  embed_template(:formatter_umbrella, """
  # Used by "mix format"
  [
    inputs: ["mix.exs", "config/*.exs"],
    subdirectories: ["apps/*"]
  ]
  """)

  embed_template(:gitignore, """
  # The directory Mix will write compiled artifacts to.
  /_build/

  # If you run "mix test --cover", coverage assets end up here.
  /cover/

  # The directory Mix downloads your dependencies sources to.
  /deps/

  # Where third-party dependencies like ExDoc output generated docs.
  /doc/

  # Ignore .fetch files in case you like to edit your project deps locally.
  /.fetch

  # If the VM crashes, it generates a dump, let's ignore it too.
  erl_crash.dump

  # Also ignore archive artifacts (built via "mix archive.build").
  *.ez
  <%= if @app do %>
  # Ignore package tarball (built via "mix hex.build").
  <%= @app %>-*.tar
  <% end %>
  # Temporary files, for example, from tests.
  /tmp/
  """)

  embed_template(:mix_exs, """
  defmodule <%= @mod %>.MixProject do
    use Mix.Project

    def project do
      [
        app: :<%= @app %>,
        version: "0.1.0",
        elixir: "~> <%= @version %>",
        start_permanent: Mix.env() == :prod,
        deps: deps()
      ]
    end

    # Run "mix help compile.app" to learn about applications.
    def application do
      [
        extra_applications: [:logger]<%= @sup_app %>
      ]
    end

    # Run "mix help deps" to learn about dependencies.
    defp deps do
      [
        # {:dep_from_hexpm, "~> 0.3.0"},
        # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
        {:ecto, "~> 3.9"}
      ]
    end
  end
  """)

  embed_template(:lib, """
  defmodule GenDSL.Model.<%= @mod %>.SampleElement do
    use Ecto.Schema
    import Ecto.Changeset
    @moduledoc \"""
    Documentation for `<%= @mod %>`.
    \"""

    schema "SampleElement" do
      field :name, :string
      field :command, :string, default: "new"
    end

    @required_fields ~w(name)a
    @optional_fields ~w(command)a

    def changeset(params \\ %{}) do
      %__MODULE__{}
        |> cast(params, @required_fields ++ @optional_fields, required: false)
        |> validate_required(@required_fields)
    end

    def to_command(%SampleElement{} = sample_element) do
      return ""
    end

    @doc \"""
    Hello world.

    ## Examples

        iex> <%= @mod %>.hello()
        :world

    \"""
    def hello do
      :world
    end


  end
  """)


  embed_template(:test, """
  defmodule <%= @mod %>Test do
    use ExUnit.Case
    doctest <%= @mod %>

    test "greets the world" do
      assert <%= @mod %>.hello() == :world
    end
  end
  """)

  embed_template(:test_helper, """
  ExUnit.start()
  """)
end
