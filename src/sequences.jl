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
    pulse_idx = vec( map(x -> reverse(collect(x)), Base.product( fill(1:num_pulses,length(qubits))... )) )
    return [ reduce(⊗, p(q) for (p,q) in zip(tomo_set[idx], qubits)) for idx in pulse_idx ]
end


"""
  state_tomo(sequence, qubits; num_pulses=4)

Applies state tomography after the `sequence` on the `qubits` using either the
4-pulse [Id, X90, Y90, X] or 6-pulse [Id, X90, X90m, Y90, Y90m, X] set of
tomographic readout pulses.
"""
function state_tomo{T<:QGL.SequenceEntry}(seq::Vector{T}, qubits::Tuple{Vararg{Qubit}}; num_pulses::Int=4)
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
    pulse_idx = vec( map(x -> reverse(collect(x)), Base.product( fill(1:length(cal_set),length(qubits))... )) )
    pulse_idx = repeat(pulse_idx, inner=num_repeats)
    return [ [reduce(⊗, p(q) for (p,q) in zip(cal_set[idx], qubits)), meas_block] for idx in pulse_idx ]
end
