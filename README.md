# QGL.jl

A performance orientated [QGL](https://github.com/BBN-Q/QGL) compiler.


## Benchmarks

Preliminary benchmarks show speed-ups for Python QGL of ~25-30X.

In the absence of proper benchmarking and regression testing we use the 1 qubit
GST sequences from [QGL issue #69](https://github.com/BBN-Q/QGL/issues/69) and
the sequence creation script in `test/benchmark.jl`. With `q1` having 20ns
pulses and 100MHz sidebanding frequency and at commit 85d937d:

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
  memory estimate:  1.22 gb
  allocs estimate:  53224096
  minimum time:     6.88 s (3.50% GC)
  median time:      6.88 s (3.50% GC)
  mean time:        6.88 s (3.50% GC)
  maximum time:     6.88 s (3.50% GC)
```
