using PyCall
@pyimport QGL

import Base: show, push!

export compile_to_hardware

immutable Event
	label::AbstractString
end

SequenceEntry = Union{Pulse, PulseBlock, ZPulse, ControlFlow, Event}

function flatten_seqs{T}(seqs::Vector{Vector{T}})
	flat_seq = Vector{SequenceEntry}()
	for seq = seqs
		push!(flat_seq, wait())
		for e in seq
			push!(flat_seq, e)
		end
	end
	return flat_seq
end

function compile_to_hardware{T}(seqs::Vector{Vector{T}}, base_filename)
	compile_to_hardware(flatten_seqs(seqs), base_filename)
end

function compile_to_hardware{T}(seq::Vector{T}, base_filename; suffix="")

	# TODO: save input code to file as metadata
	#save_code(seq)

	# add slave trigger to every WAIT
	add_slave_trigger!(seq, Marker("slaveTrig"))

	# propagate frame changes to edges
	propagate_frame_change!(seq)

	# TODO: add gating/blanking pulses
	#add_gate_pulses!(seq)

	# TODO: gating constraints
	# TODO: move to device drivers
	#apply_gating_constraints!(seq)

	seqs, pulses, chans = compile(seq)

	# normalize and inject the channel delays
	chan_lib = QGL.pyQGL.ChannelLibrary[:channelLib][:channelDict]
	chan_delays = Dict(chan => chan_lib[chan.awg_channel][:delay] for chan in chans)
	normalize_channel_delays!(chan_delays)
	inject_channel_delays!(seqs, pulses, chan_delays)

	# map the labeled channels to physical channels and bundle per APS/AWG
	AWGs = Dict{String, Dict}()
	for chan in chans
		# look up AWG and channel from convention of AWG-chan
		# TODO: make native and explicit
		(awg, chan_str) = split(chan.awg_channel, '-')
		# TODO: map is currently only for APS2 - should be looked up from somewhere
		chan_str_map = Dict("12"=>:ch12, "12m1"=>:m1, "12m2"=>:m2, "12m3"=>:m3, "12m4"=>:m4)
		get!(AWGs, awg, Dict{Symbol, Channel}())[chan_str_map[chan_str]] = chan
	end

	translator_map = Dict("APS2Pattern" => APS2)
	for (awg, ch_map) in AWGs
		# use first channel to lookup translator from pyQGL
		# TODO: make native and explicit
		first_chan = collect(values(ch_map))[1]
		phys_chan = chan_lib[first_chan.awg_channel]
		translator = translator_map[ phys_chan[:translator] ]
		translator.write_sequence_file(base_filename*"-$awg.h5", seqs, pulses, ch_map)
	end
	return seqs
end

function add_slave_trigger!(seq, slave_trig_chan)
	wait_entry = wait()
	slave_trig = Pulse("TRIG", slave_trig_chan, slave_trig_chan.shape_params["length"], 1.0)
	for (ct,e) in enumerate(seq)
		if e == wait_entry
			# try to add to next entry
			seq[ct+1] = slave_trig ⊗ seq[ct+1]
		end
	end
end

function propagate_frame_change!(seq)
	#get a dictionary of target qubits and their edges
	qs = qubits(seq)
	edges = Dict(q => Set{Edge}() for q in qs)
	for q in qs
		chan_py = QGL.pyQGL.QubitFactory(q.label)
		for predecessor in QGL.pyQGL.ChannelLibrary[:channelLib][:connectivityG][:predecessors](chan_py)
			edge = Edge(Qubit(predecessor[:label]), q)
			push!(edges[q], edge)
		end
	end
	# if there are no edges then we're finished here
	all(isempty(s) for s in values(edges)) && return

	# keep a cache of propagated Z pulses
	Z_edges = Dict{Tuple{Qubit, Float64}, PulseBlock}()

	#for any ZPulse at the target qubit, add ZPulse on its edges
	for (ct,entry) in enumerate(seq)
		if typeof(entry) == PulseBlock
			for (ch, e) in entry.pulses
				for pulse in e
					if typeof(pulse) == ZPulse && typeof(ch) == Qubit && ~isempty(edges[ch])
						if !((ch, pulse.angle) in keys(Z_edges))
							Z_edges[(ch, pulse.angle)] = reduce(⊗, [Z(x, pulse.angle) for x in edges[ch]])
						end
						insert!(seq, ct+1, Z_edges[(ch, pulse.angle)])
					end
				end
			end
		elseif typeof(entry) == ZPulse && typeof(entry.channel) == Qubit && ~isempty(edges[entry.channel])
			if !((entry.channel, entry.angle) in keys(Z_edges))
				Z_edges[(entry.channel, entry.angle)] = reduce(⊗, [Z(x, entry.angle) for x in edges[entry.channel]])
			end
			insert!(seq, ct+1, Z_edges[(entry.channel, entry.angle)])
		end
	end
end

function compile(seq)
	# find what channels we're dealing with here
	chans = channels(seq)
	seqs = Vector{SequenceEntry}()
	pulses = Dict(chan => Set{Pulse}() for chan in chans)
	paddings = Dict(chan => 0.0 for chan in chans)

	# step through sequence and schedule
	for entry in seq
		if typeof(entry) == ControlFlow
			# control flow resets clock
			if length(seqs) > 0 && typeof(seqs[end]) != ControlFlow
				for chan in chans
					apply_padding!(chan, seqs[end], paddings, pulses)
				end
			end
			push!(seqs, entry)
		else
			if (length(seqs) == 0) || (typeof(seqs[end]) == ControlFlow)
				push!(seqs, PulseBlock(chans))
			end
			push!(seqs[end], entry, pulses, paddings)
		end
	end

	# assume we want to loop to the beginning
	for chan in chans
		apply_padding!(chan, seqs[end], paddings, pulses)
	end
	push!(seqs, goto(0))

	return seqs, pulses, chans
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

function qubits(seq)
	chans = channels(seq)
	for chan in chans
		if typeof(chan) != Qubit
			delete!(chans, chan)
		end
	end
	return chans
end

"""
Shifts global channel delay such that all delays are >= 0
"""
function normalize_channel_delays!(chan_delays)
	min_delay = minimum(values(chan_delays))
	for (c,d) in chan_delays
		chan_delays[c] -= min_delay
	end
end

function inject_channel_delays!(seqs, pulses, chan_delays)

	delay_block = PulseBlock(collect(keys(chan_delays)))

	for (c,d) in chan_delays
		if d > 0
			p = QGL.Id(c, d)
			push!(delay_block.pulses[c], p)
			push!(pulses[c], p)
		end
	end

	for ct = length(seqs):-1:1
		if typeof(seqs[ct]) == QGL.ControlFlow && (seqs[ct].op == QGL.WAIT || seqs[ct].op == QGL.SYNC)
			insert!(seqs, ct+1, delay_block)
		end
	end
end


function push!(pb_cur::PulseBlock, pb_new::PulseBlock, pulses, paddings)
	pb_new_length = length(pb_new)
	for chan in channels(pb_cur)
		if chan in channels(pb_new)
			apply_padding!(chan, pb_cur, paddings, pulses)
			for p in pb_new.pulses[chan]
				#elide zero-length Pulses
				if typeof(p) == Pulse && length(p) == 0
					continue
				end
				push!(pb_cur.pulses[chan], p)
				if typeof(p) == Pulse
					push!(pulses[chan], p)
				end
			end
			paddings[chan] += pb_new_length - sum(length(p) for p in pb_new.pulses[chan])
		else
			paddings[chan] += pb_new_length
		end
	end
end

function push!{T<:Union{Pulse, ZPulse}}(pb_cur::PulseBlock, p::T, pulses, paddings)
	for chan in channels(pb_cur)
		if chan == p.channel
			apply_padding!(chan, pb_cur, paddings, pulses)
			push!(pb_cur.pulses[chan], p)
			if typeof(p) == Pulse
				push!(pulses[chan], p)
			end
		else
			paddings[chan] += length(p)
		end
	end
end

function apply_padding!(chan, pb, paddings, pulses)
	if paddings[chan] > 0.0
		pad_pulse = Id(chan, paddings[chan])
		push!(pb.pulses[chan], pad_pulse)
		push!(pulses[chan], pad_pulse)
		paddings[chan] = 0.0
	end
end
