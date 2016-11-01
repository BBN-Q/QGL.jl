# translator for the APS2
module APS2

using QGL: Pulse, waveform

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
const TRIG = 0x01
const WAIT = 0x02
const LOAD_REPEAT = 0x03
const DEC_REPEAT = 0x04
const CMP = 0x05
const GOTO = 0x06
const CALL = 0x07
const RET = 0x08
const SYNC = 0x09
const MODULATOR = 0x0a
const LOAD_CMP = 0x0b
const PREFETCH = 0x0c

typealias APS2Instruction UInt64

immutable Waveform
	address::UInt32
	count::UInt32
	isTA::Bool
	write_flag::Bool
	instruction::UInt64
end

# WFM/MARKER op codes
const PLAY_WFM = 0x0
const WAIT_TRIG = 0x1
const WAIT_SYNC = 0x2
const WFM_PREFETCH = 0x3
const WFM_OP_OFFSET = 46
const TA_PAIR_BIT = 45
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
	count::UInt32
	state::Bool
	write_flag::Bool
	instruction::UInt64
end

immutable ControlFlow
	instruction::UInt64
end

function write_sequence_file(seqs, pulses)

	# TODO: inject modulation commands
	# inject_modulation_commands

	# translate pulses to waveforms
	wf_lib, wfs = create_wfs(pulses)

	# create instructions and waveforms
	instrs = create_instructions(seqs, wf_lib)

	# TODO: write to file
end

const USE_PHASE_OFFSET_INSTRUCTION = false

function create_wfs(pulses)
	# TODO: better handle Id so we don't generate useless long wfs and have repeated 0 offsets
	wf_lib = Dict{Pulse, APS2Instruction}()
	wfs = Vector{Vector{Complex128}}()
	idx = 0
	for p in pulses
		wf = p.amp * waveform(p, DAC_CLOCK)
		if !USE_PHASE_OFFSET_INSTRUCTION
			wf *= exp(1im * p.phase)
		end
		isTA = all(wf .== wf[1])
		if isTA
			wf_lib[p] = Waveform(idx, ADDRESS_UNIT, isTA, true).instruction
			idx += ADDRESS_UNIT
			push!(wfs, wf[1:ADDRESS_UNIT])
		else
			wf_lib[p] = Waveform(idx, length(wf), isTA, true).instruction
			idx += length(wf)
			push!(wfs, wf)
		end
	end
	return wf_lib, wfs
end

function create_instrs(seqs)
	instrs = APS2Instruction[]

	time_stamps = Dict(chan => 0.0 for chan in keys(seqs))
	all_done = Dict(chan => false for chan in keys(seqs))
	idx = Dict(chan => 0 for chan in keys(seqs))

	while !all(values(all_done))
		for chan in keys(seqs)

		end

	end


end
