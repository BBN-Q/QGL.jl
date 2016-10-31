using PyCall
@pyimport QGL

import Base.show

include("pulses.jl")
include("controlflow.jl")

immutable Event
	label::AbstractString
end

SequenceEntry = Union{Pulse, PulseBlock, ControlFlow, Event}

function flatten_seqs(seq::Vector{Vector{Pulse}})
	flat_seq = Vector{SequenceEntry}()
	for seq = seqs
		push!(flat_seq, WAIT())
		for e in seq
			push!(flat_seq, e)
		end
	end
	return flat_seq
end

function compile_to_hardware(seq::Vector{Vector{Pulse}}, base_filename)
	compile_to_hardware(flatten_seqs(seq), base_filename)
end

function compile_to_hardware(seq::Vector{SequenceEntry}, base_filename; suffix="")

	# TODO: save input code to file as metadata
	#save_code(seq)

	# add slave trigger to every WAIT
	add_slave_trigger!(seq, Marker("slaveTrig"))

	# TODO: add gating/blanking pulses
	#add_gate_pulses!(seq)

	# TODO: gating constraints
	# TODO: move to device drivers
	#apply_gating_constraints!(seq)

	seqs = compile(seq)

	# TODO: dispatch to hardware instruction writer
	#write_sequence_file(seq)

	return seqs
end

function add_slave_trigger!(seq, slave_trig_chan)
	wait_entry = WAIT()
	slave_trig = Pulse("TRIG", slave_trig_chan, slave_trig_chan.shape_params["length"], 1.0, 0.0, 0.0, 0.0)
	for (ct,e) in enumerate(seq)
		if e == wait_entry
			# try to add to next entry
			seq[ct+1] = slave_trig ⊗ seq[ct+1]
		end
	end
end

function compile(seq)
	# find what channels we're dealing with here
	chans = channels(seq)
	seqs = Dict(chan => SequenceEntry[] for chan in chans)
	pulses = Dict(chan => Set{Pulse}() for chan in chans)
	paddings = Dict(chan => 0.0 for chan in chans)

	# step through sequence and schedule
	for e in seq
		schedule!(seqs, pulses, paddings, e)
	end

	return seqs
end

function channels(seq)
	chans = Set{Channel}()
	for e in seq
		if typeof(e) == Pulse
			push!(chans, e.channel)
		elseif typeof(e) == PulseBlock
			for chan in keys(e.pulses)
				push!(chans, chan)
			end
		end
	end
	return chans
end

function schedule!(seqs, pulses, paddings, cf::ControlFlow)
	# broadcast control flow
	for chan in keys(seqs)
		apply_padding!(chan, seqs, paddings, pulses)
		push!(seqs[chan], cf)
	end
end

function schedule!(seqs, pulses, paddings, pb::PulseBlock)
	pb_length = length(pb)
	for chan in keys(seqs)
		if chan in keys(pb.pulses)
			for p in pb.pulses[chan]
				push!(seqs[p.channel], p)
				push!(pulses[p.channel], p)
			end
			paddings[chan] += pb_length - sum(p.length for p in pb.pulses[chan])
		else
			paddings[chan] += pb_length
		end
	end
end

function schedule!(seqs, pulses, paddings, p::Pulse)
	for chan in keys(seqs)
		if chan == p.channel
			apply_padding!(chan, seqs, paddings, pulses)
			push!(seqs[p.channel], p)
			push!(pulses[p.channel], p)
		else
			paddings[chan] += length(p)
		end
	end
end

function apply_padding!(chan, seqs, paddings, pulses)
	if paddings[chan] > 0.0
		pad_pulse = Id(chan, paddings[chan])
		push!(seqs[chan], pad_pulse)
		push!(pulses[chan], pad_pulse)
		paddings[chan] = 0.0
	end
end
