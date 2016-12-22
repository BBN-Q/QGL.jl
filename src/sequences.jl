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

function state_tomo{T<:QGL.SequenceEntry}(seq::Vector{T}, qubits::Tuple{Vararg{Qubit}}; num_pulses::Int=4)
    meas_block = reduce(⊗, MEAS(q) for q in qubits)
    return [[seq; tomo_block; meas_block] for tomo_block in tomo_blocks(qubits; num_pulses=num_pulses)]
end

function cal_seqs(qubits::Tuple{Vararg{Qubit}}; num_repeats::Int=2)
    cal_set = [Id, X]
    meas_block = reduce(⊗, MEAS(q) for q in qubits)
    # TODO: replace with lexproduct when https://github.com/JuliaLang/julia/pull/18825 is merged
    pulse_idx = vec( map(x -> reverse(collect(x)), Base.product( fill(1:length(cal_set),length(qubits))... )) )
    pulse_idx = repeat(pulse_idx, inner=num_repeats)
    return[ [reduce(⊗, p(q) for (p,q) in zip(cal_set[idx], qubits)), meas_block] for idx in pulse_idx ]
end
