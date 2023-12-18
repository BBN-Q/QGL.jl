export state_tomo, cal_seqs

function tomo_blocks(qubits::Tuple{Vararg{Qubit}}; num_pulses::Int=4)
    if num_pulses == 4
        tomo_set = [Id, X90, Y90, X]
    elseif num_pulses == 6
        tomo_set = [Id, X90, X90m, Y90, Y90m, X]
    else
        error("Only able to handle num_pulses=4 or 6")
    end
    # TODO: replace with lexproduct when https://github.com/JuliaLang/julia/pull/18825 is merged
    pulse_combos = map(reverse, Base.product( fill(tomo_set, length(qubits))... ))
    return [ reduce(⊗, p(q) for (p,q) in zip(pulses, qubits)) for pulses in vec(pulse_combos) ]
end

"""
  state_tomo(sequence, qubits; num_pulses=4)

Applies state tomography after the `sequence` on the `qubits` using either the
4-pulse [Id, X90, Y90, X] or 6-pulse [Id, X90, X90m, Y90, Y90m, X] set of
tomographic readout pulses.
"""
function state_tomo(seq::Vector{T}, qubits::Tuple{Vararg{Qubit}}; num_pulses::Int=4) where {T<:QGL.SequenceEntry}
    meas_block = reduce(⊗, MEAS(q) for q in qubits)
    return [[seq; tomo_block; meas_block] for tomo_block in tomo_blocks(qubits; num_pulses=num_pulses)]
end

"""
  cal_seqs(qubits; num_repeats=2)

Returns an array of "calibration sequences" - all combinations in
lexicographical order of Id and X pulses for the `qubits` followed by the
measurement block. To enhance the visuals or estimate noise the sequences can be
inner repeated by `num_repeats`.

# Example
```julia
julia> cal_seqs((q1,q2); num_repeats=2)
8-element Array{Array{QGL.PulseBlock,1},1}:
 QGL.PulseBlock[(Id(q1))⊗(Id(q2)),(MEAS(M-q1))⊗(MEAS(M-q2))⊗(TRIG(digitizerTrig))]
 QGL.PulseBlock[(Id(q1))⊗(Id(q2)),(MEAS(M-q1))⊗(MEAS(M-q2))⊗(TRIG(digitizerTrig))]
 QGL.PulseBlock[(Id(q1))⊗(X(q2)),(MEAS(M-q1))⊗(MEAS(M-q2))⊗(TRIG(digitizerTrig))]
 QGL.PulseBlock[(Id(q1))⊗(X(q2)),(MEAS(M-q1))⊗(MEAS(M-q2))⊗(TRIG(digitizerTrig))]
 QGL.PulseBlock[(X(q1))⊗(Id(q2)),(MEAS(M-q1))⊗(MEAS(M-q2))⊗(TRIG(digitizerTrig))]
 QGL.PulseBlock[(X(q1))⊗(Id(q2)),(MEAS(M-q1))⊗(MEAS(M-q2))⊗(TRIG(digitizerTrig))]
 QGL.PulseBlock[(X(q1))⊗(X(q2)),(MEAS(M-q1))⊗(MEAS(M-q2))⊗(TRIG(digitizerTrig))]
 QGL.PulseBlock[(X(q1))⊗(X(q2)),(MEAS(M-q1))⊗(MEAS(M-q2))⊗(TRIG(digitizerTrig))]
```
"""
function cal_seqs(qubits::Tuple{Vararg{Qubit}}; num_repeats::Int=2)
    cal_set = [Id, X]
    meas_block = reduce(⊗, MEAS(q) for q in qubits)
    # TODO: replace with lexproduct when https://github.com/JuliaLang/julia/pull/18825 is merged
    pulse_combos = map(reverse, Base.product( fill(cal_set, length(qubits))... ))
    pulse_combos = repeat(vec(pulse_combos), inner=num_repeats)
    return [ [reduce(⊗, p(q) for (p,q) in zip(pulses, qubits)), meas_block] for pulses in pulse_combos]
end

"""
Create and optionally compile a RabiWidth experiment for a single qubit assuming
a tanh pulse shape and a piAmp amplitude

RabiWidth(qubit, pulseSpacings; compile=true)

Parameters
-------
qubit           : qubit in scope
pulseSpacings   : iterable of experiment time steps in seconds
compile         : if true, compile the sequence to .h5 files

Returns
-------
seqs            : Array of sequences

Ex: RabiWidth(q, 1e-9*linspace(10, 2010, 201))
"""
function RabiWidth(qubit, pulseSpacings; compile::Bool=true)
    qubit.shape_params[:shape_function] = QGL.PulseShapes.tanh;
	seqs = [[Uθ(qubit, len, qubit.shape_params[:piAmp], 0., qubit.frequency, qubit.shape_params),
        MEAS(qubit)] for len in pulseSpacings]
    if compile
	   compile_to_hardware(seqs, "Rabi");
    end
    return seqs
end

"""
Create and optionally compile a RabiAmp experiment for a single qubit

RabiWidth(qubit, amps; compile=true)

Parameters
-------
qubit           : qubit in scope
amps            : iterable of experiment amplitudes [-1,1]
compile         : if true, compile the sequence to .h5 files

Returns
-------
seqs            : Array of sequences

Ex: RabiAmp(q, linspace(-1, 1, 101))
"""

function RabiAmp(qubit, amps; compile::Bool=true)
	seqs = [[Uθ(qubit, qubit.shape_params[:length], amp, 0.),
        MEAS(qubit)] for amp in amps]
    if compile
        compile_to_hardware(seqs, "Rabi");
    end
    return seqs
end

"""
Create and optionally compile a T1 experiment for a single qubit

InversionRecovery(qubit, amps; compile=true)

qubit           : qubit in scope
pulseSpacings   : iterable of experiment time steps in seconds
compile         : if true, compile the sequence to .h5 files

returns         : Array of sequences

Ex: InversionRecovery(q, 1e-9*linspace(10, 2010, 201))
"""

function InversionRecovery(qubit, pulseSpacings; num_repeats::Int=2, compile::Bool=true)
	seqs = [[X(qubit), Id(qubit,len), MEAS(qubit)] for len in pulseSpacings];
    cals = cal_seqs((qubit,), num_repeats = num_repeats);
    seqs = append!(seqs, cals);
    if compile
        compile_to_hardware(seqs, "T1");
    end
    return seqs
end

"""
Create and optionally compile a Ramsey experiment for a single qubit

Ramsey(qubit, pulseSpacings; TPPIFreq::Float64=0.0, num_repeats::Int=2, compile=true)

Parameters
-------
qubit           : qubit in scope
pulseSpacings   : iterable of experiment time steps in seconds
TPPIFreq        : time-proportinal phase increment frequency in Hz
num_repeats     : number of calibration repeats
compile         : if true, compile the sequence to .h5 files

Returns
-------
seqs            : Array of sequences

Ex: Ramsey(q, 1e-9*linspace(10, 2010, 201))

"""
function Ramsey(qubit, pulseSpacings; TPPIFreq::Float64=0.0, num_repeats::Int=2, compile::Bool=true)
    phases = TPPIFreq * pulseSpacings

    seqs = [[X90(qubit), Id(qubit, l), Uθ(qubit, qubit.shape_params[:length],
        qubit.shape_params[:pi2Amp], phase), MEAS(qubit)] for (l, phase) in zip(pulseSpacings, phases)];
    cals = cal_seqs((qubit,), num_repeats = num_repeats);
    seqs = append!(seqs, cals);
    if compile
        compile_to_hardware(seqs, "Ramsey");
    end
    return seqs
end
