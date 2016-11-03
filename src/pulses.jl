import Base: convert, promote_rule, length

export X90, Y90, X, Y, Id, ⊗

immutable Pulse
	label::AbstractString
	channel
	length::Real
	amp::Real
	phase::Real
	frequency::Real
	frame_change::Real
end

Pulse(label, channel) = Pulse(label, channel, 0.0, 0.0, 0.0, 0.0, 0.0)
Pulse(label, channel, length) = Pulse(label, channel, length, 0.0, 0.0, 0.0, 0.0)
Pulse(label, channel, length, amp) = Pulse(label, channel, length, amp, 0.0, 0.0, 0.0)
Pulse(label, channel, length, amp, phase) = Pulse(label, channel, length, amp, phase, 0.0, 0.0)

show(io::IO, p::Pulse) = print(io, "$(p.label)($(p.channel.label))")

X90(q::Qubit)::Pulse =
	Pulse("X90", q, q.shape_params["length"], q.shape_params["pi2Amp"])

Y90(q::Qubit)::Pulse =
	Pulse("Y90", q, q.shape_params["length"], q.shape_params["pi2Amp"])

X(q::Qubit)::Pulse =
	Pulse("X", q, q.shape_params["length"], q.shape_params["piAmp"], 0.25)

Y(q::Qubit)::Pulse =
	Pulse("Y", q, q.shape_params["length"], q.shape_params["piAmp"], 0.25)

function Id(c::Channel, length)
	# TODO: inject constant pulse shape
	Pulse("Id", c, length, 0.0)
end
Id(c::Channel) = Id(c, c.shape_params["length"])

type PulseBlock
	pulses::Dict{Channel, Vector{Pulse}}
end

convert(::Type{PulseBlock}, p::Pulse) = PulseBlock(Dict(p.channel => [p]))
PulseBlock(p::Pulse) = convert(PulseBlock, p)
PulseBlock(chans::Set{Channel}) = PulseBlock(Dict{Channel, Vector{Pulse}}(chan => Pulse[] for chan in chans))
⊗(x::Pulse, y::Pulse) = ⊗(PulseBlock(x), PulseBlock(y))
⊗(x::Pulse, y::PulseBlock) = ⊗(PulseBlock(x), y)
⊗(x::PulseBlock, y::PulseBlock) = PulseBlock(merge(x.pulses, y.pulses))
promote_rule(::Type{Pulse}, ::Type{PulseBlock}) = PulseBlock

channels(pb::PulseBlock) = keys(pb.pulses)

function show(io::IO, pb::PulseBlock)
	strs = []
	for ps = values(pb.pulses)
		push!(strs, "(" * join([string(p) for p in ps], ",") * ")")
	end
	str = join(strs, "⊗")
	print(io, "[$str]")
end

length(p::Pulse) = p.length
length(pb::PulseBlock) = maximum(sum(p.length for p in ps) for ps in values(pb.pulses))


# TODO: make native and handle TA pairs
function waveform(p::Pulse, sampling_rate)
	# copy shape parameters from channel and convert to symbols to splat in call below
	shape_params = Dict(Symbol(k) => v for (k,v) in p.channel.shape_params)
	shape_params[:samplingRate] = sampling_rate
	shape_params[:length] = p.length
	return shape_params[:shapeFun](;shape_params...)
end
