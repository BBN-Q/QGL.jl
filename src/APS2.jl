# translator for the APS2
module APS2

import Base: convert

using HDF5

import QGL

import ..config

const DAC_CLOCK = 1.2e9
const FPGA_CLOCK = 300e6
const ADDRESS_UNIT = 4  #everything is done in units of 4 timesteps
const MIN_ENTRY_LENGTH = 8
const MAX_WAVEFORM_PTS = 2^28  #maximum size of waveform memory
const WAVEFORM_CACHE_SIZE = 2^17
const MAX_WAVEFORM_VALUE = 2^13 - 1  #maximum waveform value i.e. 14bit DAC
const MAX_NUM_INSTRUCTIONS = 2^26
const MAX_REPEAT_COUNT = 2^16 - 1
const MAX_MARKER_COUNT = 2^32 - 1

# instruction encodings
const WFM = 0x00
const MARKER = 0x01
const WAIT = 0x02
const LOAD_REPEAT = 0x03
const DEC_REPEAT = 0x04
const CMP = 0x05
const GOTO = 0x06
const CALL = 0x07
const RETURN = 0x08
const SYNC = 0x09
const MODULATOR = 0x0a
const LOAD_CMP = 0x0b
const PREFETCH = 0x0c

const APS2Instruction = UInt64

immutable Waveform
	address::UInt32
	count::UInt32
	isTA::Bool
	write_flag::Bool
	instruction::UInt64
end

# WFM/MARKER op codes
const PLAY_WFM      = 0x0
const WAIT_TRIG     = 0x1
const WAIT_SYNC     = 0x2
const WFM_PREFETCH  = 0x3
const WFM_OP_OFFSET = 46
const TA_PAIR_BIT   = 45
const WFM_CT_OFFSET = 24

function Waveform(address, count, isTA, write_flag)
	ct = UInt64(count ÷ ADDRESS_UNIT - 1) & 0x000f_ffff # 20 bit count
	addr = UInt64(address ÷ ADDRESS_UNIT) & 0x00ff_ffff # 24 bit address
	header = UInt64( (WFM << 4) | (0x3 << 2) | (write_flag & 0x1) )
	payload = (UInt64(PLAY_WFM) << WFM_OP_OFFSET) | (UInt64(isTA) << TA_PAIR_BIT) | (ct << WFM_CT_OFFSET) | addr
	instr = (header << 56) | payload
	Waveform(addr, ct, isTA, write_flag, instr)
end

immutable Marker
	engine_select::UInt8
	state::Bool
	count::UInt32
	transition_word::UInt8
	write_flag::Bool
	instruction::UInt64
end

function Marker(marker_select, count, state, write_flag)
	count = UInt64(count)
	quad_count =  UInt64(count) ÷ ADDRESS_UNIT & UInt64(0x0fff_ffff) # 28 bit count
	count_rem = count % ADDRESS_UNIT
	if state
		transition_words = [0b1111; 0b0111; 0b0011; 0b0001]
		transition_word = transition_words[count_rem+1]
	else
		transition_words = [0b0000; 0b1000; 0b1100; 0b1110]
		transition_word = transition_words[count_rem+1]
	end
	header = (MARKER << 4) | (((marker_select-1) & 0x3) << 2) | (write_flag & 0x1)
	payload = (UInt64(PLAY_WFM) << WFM_OP_OFFSET) | (UInt64(transition_word) << 33) | (UInt64(state) << 32) | quad_count
	instr = (UInt64(header) << 56) | payload
	Marker(UInt8(marker_select), state, quad_count, transition_word, write_flag, instr)
end

immutable ControlFlow
	instruction::UInt64
end


# modulation instructions
@enum MODULATION_OP_CODE MODULATE=0x00 RESET_PHASE=0x02 SET_FREQ=0x06 SET_PHASE=0x0a UPDATE_FRAME=0x0e
const MODULATOR_OP_OFFSET = 44
const NCO_SELECT_OP_OFFSET = 40
function modulation_instr(op::MODULATION_OP_CODE, nco_select, payload=0)
	return UInt64(MODULATOR) << 60 | UInt64(0x1) << 56 |
		UInt64(op) << MODULATOR_OP_OFFSET | UInt64(nco_select) << 40 |
		reinterpret(UInt32, Int32(payload))
end


"""
Serialize a pulse sequence to a HDF5 file
"""
function write_sequence_file(filename, seqs, pulses, channel_map)

	# check whether there is any analog data
	markers_only = !(:ch12 in keys(channel_map))
	# translate pulses to waveform and/or markers
	instr_lib = Dict{QGL.Pulse, Union{Waveform,Marker}}()
	chan_freqs = Dict{QGL.Channel, Float64}()
	wfs = Vector{Vector{Complex{Int16}}}()
	if !markers_only
		for ch in channel_map[:ch12]
			chan_freqs[ch] = ch.frequency
			create_wf_instrs!(instr_lib, wfs, pulses[ch])
		end
	end
	for (ct, marker_chan) = enumerate([:m1, :m2, :m3, :m4])
		if marker_chan in keys(channel_map)
			create_marker_instrs!(instr_lib, pulses[channel_map[marker_chan][1]], ct)
		end
	end

	# create instructions
	instrs = create_instrs(seqs, instr_lib, collect(values(channel_map)), chan_freqs)

	write_to_file(filename, instrs, wfs)
end

const USE_PHASE_OFFSET_INSTRUCTION = false
const USE_PULSE_FREQUENCY_INSTRUCTION = false

function create_wf_instrs!(instr_lib, wfs, pulses)
	# TODO: better handle Id so we don't generate useless long wfs and have repeated TAZ offsets
	idx = 0
	for p in pulses
		wf = p.amp * QGL.waveform(p, DAC_CLOCK)
		if !USE_PHASE_OFFSET_INSTRUCTION
			wf *= exp(1im * 2π * p.phase)
		end
		if !USE_PULSE_FREQUENCY_INSTRUCTION && p.frequency != 0
			# bake the pulse frequency into the waveform
			wf .*= exp(-1im * 2π * p.frequency * (1/DAC_CLOCK) * (1:length(wf)) )
		end
		# reduce to Int16 with maximum for 14 bit DAC
		wf = round(Int16, MAX_WAVEFORM_VALUE*real(wf)) + 1im*round(Int16, MAX_WAVEFORM_VALUE*imag(wf))

		isTA = all(wf .== wf[1])
		instr_lib[p] = Waveform(idx, length(wf), isTA, true)
		if isTA
			idx += ADDRESS_UNIT
			push!(wfs, wf[1:ADDRESS_UNIT])
		else
			idx += length(wf)
			push!(wfs, wf)
		end
	end

	return wfs
end

function create_marker_instrs!(instr_lib, pulses, marker_chan)
	for p in pulses
		num_points = round(UInt64, length(p) * DAC_CLOCK)
		instr_lib[p] = Marker(marker_chan, num_points, p.amp > 0.5, true)
	end
end


function find_next_analog_entry!(entry, chan, wf_lib, analog_timestamps, id_ch, Z_chs_id)
	if any([id_ch[ct] > length(entry.pulses[chan[ct]]) for ct in length(chan)])
		return
	end
	sim_chs_id = find(x-> x == minimum(analog_timestamps), analog_timestamps)
	filter!(x->!(x in Z_chs_id), sim_chs_id)
	pulses = []
	for ct in sim_chs_id
		pulse = entry.pulses[chan[ct]][id_ch[ct]]
		if typeof(pulse) == QGL.ZPulse
			if length(sim_chs_id) > 1 #if simultaneous logical channels, remove the Z pulses one by one
				push!(Z_chs_id, ct)
			end
			id_ch[ct]+=1
			return pulse
		end
		push!(pulses, pulse)
	end
	if length(sim_chs_id) == 1
		chan_select = sim_chs_id[1]
	else
		#select pulses on simultaneous channels
		nonid_ids = find([!wf_lib[pulse].isTA for pulse in pulses]) #find non-Id pulses
		if length(nonid_ids) > 1
			error("Only a single non-Id channel allowed")
		elseif length(nonid_ids) == 1
			chan_select = sim_chs_id[nonid_ids[1]]
		else #select the channel with the shortest Id
			chan_select = sim_chs_id[indmin([pulse.length for pulse in pulses])]
		end
	end
	next_entry = entry.pulses[chan[chan_select]][id_ch[chan_select]]
	for ct in sim_chs_id
		analog_timestamps[ct] += wf_lib[entry.pulses[chan[ct]][id_ch[ct]]].count + 1
		id_ch[ct]+=1
	end
	Z_chs_id = []
	return next_entry
end

function create_instrs(seqs, wf_lib, chans, chan_freqs)
	instrs = APS2Instruction[]

	# TODO: sort out whether we need any modulation commands
	# freqs = any(e.frequency != 0 for e in seqs if typeof(e) == QGL.Pulse)
	# frame_changes = any(typeof(e) == QGL.ZPulse for e in seqs)

	num_chans = length(chans)
	time_stamp = zeros(Int, num_chans)
	idx = ones(Int, num_chans)
	all_done = zeros(Bool, num_chans)
	num_entries = zeros(Int, num_chans)

	reset_phase_instr = modulation_instr(RESET_PHASE, 0x7)
	sync_instr = convert(APS2Instruction, QGL.sync())
	chan_freq_instrs = APS2Instruction[]
	if !isempty(chan_freqs)
		nco_select = Dict{QGL.Channel, UInt8}(chan => ct for (ct, chan) in enumerate(keys(chan_freqs)))
		for (chan, freq) in chan_freqs
			push!(chan_freq_instrs, modulation_instr(SET_FREQ, nco_select[chan], round(Int32, -freq / FPGA_CLOCK * 2^28 )) )
		end
	end

	for entry in seqs
		if typeof(entry) == QGL.PulseBlock
			# zero-out status vectors
			fill!(time_stamp, 0)
			fill!(idx, 1)
			for (ct, chan) in enumerate(chans)
				num_entries[ct] = minimum([length(entry.pulses[ch]) for ch in chan])
				all_done[ct] = num_entries[ct] == 0
			end

			analog_timestamps = zeros(Int, length(chan_freqs))
			analog_idx = ones(Int, length(chan_freqs))
			Z_chs_id = []
			# serialize pulses from the PulseBlock
			# round-robin through the channels until all are exhausted
			while !all(all_done)
				next_instr_time = minimum(time_stamp)

				for (ct, chan) in enumerate(chans)
					if (!all_done[ct]) && (time_stamp[ct] <= next_instr_time)

						if length(chan)>1 # multiple logical channels per analog channel
							next_entry = find_next_analog_entry!(entry, chan, wf_lib, analog_timestamps, analog_idx, Z_chs_id)
							if typeof(next_entry) == Void
								all_done[ct] = true
								break
							end
						else
							next_entry = entry.pulses[chan[1]][idx[ct]]
							idx[ct] += 1
							all_done[ct] = idx[ct] > num_entries[ct]
						end
						if typeof(next_entry) == QGL.Pulse
							wf = wf_lib[next_entry]
							if typeof(next_entry.channel) == QGL.Qubit || typeof(next_entry.channel) == QGL.Edge
								# TODO: inject frequency update if necessary
								push!(instrs, modulation_instr(MODULATE, nco_select[next_entry.channel], wf.count))
							end
							push!(instrs, wf.instruction)
							time_stamp[ct] += wf.count+1
						elseif typeof(next_entry) == QGL.ZPulse
							# round phase to 28 bit integer
							fixed_pt_phase = round(Int32, mod(-next_entry.angle, 1) * 2^28 )
							push!(instrs, modulation_instr(UPDATE_FRAME, nco_select[next_entry.channel], fixed_pt_phase))
							# if the Z pulse is the first thing after a WAIT then we need to inject it before the WAIT
							if ((instrs[end-1] >> 60) & 0xff) == WAIT
								instrs[[end-1,end]] = instrs[[end, end-1]]
							end
						else
							error("Untranslated pulse block entry")
						end


					end

				end
			end

		else # if it's not a PulseBlock it must be a ControlFlow operation
			# convert control flow to APS2Instruction
			if entry.op == QGL.WAIT
				# heuristic to inject SYNC before a wait
				push!(instrs, sync_instr)
				# heuristic to reset modulation engine phase set frequency before wait for trigger
				push!(instrs, reset_phase_instr)
				for instr in chan_freq_instrs
					push!(instrs, instr)
				end
			end
			push!(instrs, convert(APS2Instruction, entry))
		end

	end

	return instrs

end

function convert(::Type{APS2Instruction}, cf::QGL.ControlFlow)
	if cf.op == QGL.WAIT
		return UInt64(WAIT << 4 | 0x1) << 56 | UInt64(WAIT_TRIG) << WFM_OP_OFFSET
	elseif cf.op == QGL.GOTO
		return UInt64(GOTO << 4 | 0x1) << 56 | UInt64(cf.target)
	elseif cf.op == QGL.SYNC
		return UInt64(SYNC << 4 | 0x1) << 56 | UInt64(WAIT_SYNC) << WFM_OP_OFFSET
	else
		error("Untranslated control flow instruction")
	end
end

function write_to_file(filename, instrs, wfs)
	# flatten waveforms to vector
	wf_vec = Vector{Complex{Int16}}()
	if !isempty(wfs)
		resize!(wf_vec, sum(length(wf) for wf in wfs))
		idx = 1
		for wf in wfs
			wf_vec[idx:idx+length(wf)-1] = wf
			idx += length(wf)
		end
	end

	#prepend the sequence directory
	seq_name_dir = filename[1:match(r"-", filename).offset-1]
	seq_path = joinpath(config.sequence_files_path, seq_name_dir)
	# create the sequence directory if necessary
	if !isdir(seq_path)
		mkpath(seq_path)
	end
	filename = joinpath(seq_path, filename)

	h5open(filename, "w") do f
		attrs(f)["Version"] = 4.0
		attrs(f)["target hardware"] = "APS2"
		attrs(f)["minimum firmware version"] = 4.0
		attrs(f)["channelDataFor"] = UInt16[1; 2]
		chan_1 = g_create(f, "chan_1")
		write(chan_1, "waveforms", real(wf_vec))
		write(chan_1, "instructions", instrs)
		chan_2 = g_create(f, "chan_2")
		write(chan_2, "waveforms", imag(wf_vec))
	end
end

end
