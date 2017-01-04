# QGL.jl

A performance orientated [QGL](https://github.com/BBN-Q/QGL) compiler.

## Installation

The package is not yet registered with METADATA.jl and so must be cloned with

```julia
Pkg.clone("https://github.com/BBN-Q/QGL.jl.git")
```

## Python QGL dependency

For now we still rely on the [python QGL]([QGL](https://github.com/BBN-Q/QGL))
being available via PyCall.jl. Make sure it is on your `PYTHONPATH` before
staring julia.

## Benchmarks

Preliminary benchmarks show speed-ups for Python QGL of ~25-30X.

In the absence of proper benchmarking and regression testing we use the 1 qubit
GST sequences from [QGL issue #69](https://github.com/BBN-Q/QGL/issues/69) and
the sequence creation script in `test/benchmark.jl`. With `q1` having 20ns
pulses and 100MHz sidebanding frequency and at commit 3a12d61:

```julia
julia> push!(LOAD_PATH, "/home/cryan/Programming/Repos/QGL.jl/src");
julia> using QGL
julia> q1 = Qubit("q1")
q1

julia> include("test/benchmark.jl")
create_1Q_GST_seqs

julia> seqs = create_1Q_GST_seqs("/home/cryan/Downloads/sequence_numbers.csv", q1);

julia> using BenchmarkTools
julia> @benchmark compile_to_hardware(seqs, "silly")
BenchmarkTools.Trial:
  samples:          1
  evals/sample:     1
  time tolerance:   5.00%
  memory tolerance: 1.00%
  memory estimate:  1.17 gb
  allocs estimate:  49861989
  minimum time:     5.87 s (3.44% GC)
  median time:      5.87 s (3.44% GC)
  mean time:        5.87 s (3.44% GC)
  maximum time:     5.87 s (3.44% GC)
```

## License

Apache License v2.0

## Funding

This work was funded in part by the Army Research Office under contract W911NF-14-C-0048.
