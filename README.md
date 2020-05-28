# QGL.jl

[![Build Status](https://travis-ci.org/BBN-Q/QGL.jl.svg?branch=master)](https://travis-ci.org/BBN-Q/QGL.jl)

A performance orientated [QGL](https://github.com/BBN-Q/QGL) compiler.

## Installation

The package is not yet registered with METADATA.jl and so must be cloned with

```julia
Pkg.clone("https://github.com/BBN-Q/QGL.jl.git")
```

### QGL dependency

The SQLite database structure is managed by the python implementation of QGL.  
This adds to the dependencies but reduces the amount of duplicated work QGL.jl 
has to do in collecting the qubit control meta-data.  To install QGL and its
deps:

```julia
using Conda
Conda.add("pip")
pip = joinpath(Conda.BINDIR, "pip")
run(`$pip install path/to/local/QGL`) # or
run(`$pip install https://github.com/BBN-Q/QGL.git`)
```

## Benchmarks

Preliminary benchmarks show speed-ups for Python QGL of ~25-30X.

In the absence of proper benchmarking and regression testing we use the 1 qubit
GST sequences from [QGL issue #69](https://github.com/BBN-Q/QGL/issues/69) and
the sequence creation script in `test/benchmark.jl`. With `q1` having 20ns
pulses and 100MHz sidebanding frequency and at commit 8fbbee6. Since it takes
5-6 seconds to compile and the default Benchmarking.jl times out with a single
run. There is some variation so it is worth running a few trials.

```julia
julia> using QGL
julia> q1 = Qubit("q1")
q1

julia> include("test/benchmark.jl")
create_1Q_GST_seqs

julia> seqs = create_1Q_GST_seqs("/home/cryan/Downloads/sequence_numbers.csv", q1);

julia> using BenchmarkTools
julia> t = @benchmark compile_to_hardware(seqs, "silly") samples=5 seconds=60
BenchmarkTools.Trial:
  memory estimate:  1.56 gb
  allocs estimate:  66356642
  --------------
  minimum time:     6.685 s (5.09% GC)
  median time:      7.104 s (5.14% GC)
  mean time:        7.091 s (5.26% GC)
  maximum time:     7.373 s (5.65% GC)
  --------------
  samples:          5
  evals/sample:     1
  time tolerance:   5.00%
  memory tolerance: 1.00%
```

## License

Apache License v2.0

## Funding

This work was funded in part by the Army Research Office under contract W911NF-14-C-0048.
