using Iterators

export state_tomo, create_cal_seqs

function create_tomo_blocks(qubits::Tuple{Vararg{Qubit}}, num_pulses::Int64 = 4)
    if num_pulses == 4
        tomo_set = [Id, X90, Y90, X]
    elseif num_pulses == 6
        tomo_set = [Id, X90, X90m, Y90, Y90m, X]
    else
        error("Only able to handle numPulses=4 or 6")
    end
    pulse_mat = product(fill(1:num_pulses,length(qubits))...)
    return [reduce(⊗, tomo_set[pulse_ind[ct]](qubits[ct]) for ct in 1:length(pulse_ind)) for pulse_ind in pulse_mat]
end

function state_tomo{T<:QGL.SequenceEntry}(seq::Vector{T}, qubits::Tuple{Vararg{Qubit}}, num_pulses::Int64 = 4)
    measBlock = reduce(⊗, [MEAS(q) for q in qubits])
    return [[seq; tomoBlock; measBlock] for tomoBlock in create_tomo_blocks(qubits, num_pulses)]
end

function create_cal_seqs(qubits::Tuple{Vararg{Qubit}}, num_repeats::Int64 = 2)
    cal_set = [Id, X]
    pulse_mat = product(fill(1:length(qubits),length(qubits))...)
    cal_seqs = [reduce(⊗, cal_set[pulse_ind[ct]](qubits[ct]) for ct in 1:length(pulse_ind)) for pulse_ind in pulse_mat for _ in 1:num_repeats]
end
