# Configure Nx for the test run. Without this, fastText inference and
# Bumblebee model traces both run on `Nx.BinaryBackend` (pure-Erlang)
# which is orders of magnitude slower than EXLA. Setting both the
# backend and the `defn` compiler matches the recommended production
# configuration.
#
# When `:exla` is not loaded (it is an optional dependency), this is a
# no-op and tests run on the default `Nx.BinaryBackend`.
if Code.ensure_loaded?(EXLA) do
  Nx.global_default_backend(EXLA.Backend)
  Nx.Defn.global_default_options(compiler: EXLA)
end

ExUnit.start(exclude: [:requires_lid_176, :requires_bumblebee_model])
