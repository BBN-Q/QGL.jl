import Base: convert, promote_rule, length

export X90, X, X90m, Y90, Y, Y90m, Z90, Z, Z90m, Id, ⊗, MEAS, AC, DiAC

immutable Pulse
	label::String
	channel::Channel
	length::Real
	amp::Real
	phase::Real
	frequency::Real
end

immutable ZPulse
	label::String
	channel
	angle::Real
end

Pulse(label::String, channel::Channel, length=0.0, amp=0.0, phase=0.0, frequency=0.0) = Pulse(label, channel, length, amp, phase, frequency)

show(io::IO, p::Pulse) = print(io, "$(p.label)($(p.channel.label))")

for (func, label, amp, phase) in [
	(:X90,  "X90",  "pi2Amp", 0),
	(:X,    "X",    "piAmp",  0),
	(:X90m, "X90m", "pi2Amp", 0.5),
	(:Y90,  "Y90",  "pi2Amp", 0.25),
	(:Y,    "Y",    "piAmp",  0.25),
	(:Y90m, "Y90m", "pi2Amp", 0.75)
	]
	@eval $func(q) = Pulse($label, q, q.shape_params["length"], q.shape_params[$amp], $phase, 0)
end

Z(q::Qubit, angle=0.5) = ZPulse("Z", q, angle)
Z90(q::Qubit) = ZPulse("Z90", q, 0.25)
Z90m(q::Qubit) = ZPulse("Z90m", q, 0.75)
length(z::ZPulse) = 0

show(io::IO, z::ZPulse) = print(io, "$(z.label)($(z.channel.label), $(z.angle))")

function Id(c::Channel, length)
	# TODO: inject constant pulse shape
	Pulse("Id", c, length, 0.0)
end
Id(c::Channel) = Id(c, c.shape_params["length"])


function AC(q::Qubit, num)

	pulses = [
		q -> Id(q),
		q -> X90(q),
		q -> X(q),
		q -> X90m(q),
		q -> Y90(q),
		q -> Y(q),
		q -> Y90m(q),
		q -> Z90(q),
		q -> Z(q),
		q -> Z90m(q)
	]

	return pulses[num](q)

end

"""
	DiAC(q, num)

	Return the single qubit Clifford `num` in "diatomic" form: Z(α) - X90 - Z(β) - X90 - Z(γ)
"""
function DiAC(q::Qubit, num)
	angles = 0.5 * [
		[ 0.0,  1.0,  1.0],
		[ 0.5, -0.5,  0.5],
		[ 0.0,  0.0,  0.0],
		[ 0.5,  0.5,  0.5],
		[ 0.0, -0.5,  1.0],
		[ 0.0,  0.0,  1.0],
		[ 0.0,  0.5,  1.0],
		[ 0.0,  1.0, -0.5],
		[ 0.0,  1.0,  0.0],
		[ 0.0,  1.0,  0.5],
		[ 0.0,  0.0,  0.5],
		[ 0.0,  0.0, -0.5],
		[ 1.0, -0.5,  1.0],
		[ 1.0,  0.5,  1.0],
		[ 0.5, -0.5, -0.5],
		[ 0.5,  0.5, -0.5],
		[ 0.5, -0.5,  1.0],
		[ 1.0, -0.5, -0.5],
		[ 0.0,  0.5, -0.5],
		[-0.5, -0.5,  1.0],
		[ 1.0,  0.5, -0.5],
		[ 0.5,  0.5,  1.0],
		[ 0.0, -0.5, -0.5],
		[-0.5,  0.5,  1.0]
		]
	return PulseBlock(Dict(q => [Z(q, angles[num][1]), X90(q), Z(q, angles[num][2]), X90(q), Z(q, angles[num][3])]))
end

type PulseBlock
	pulses::Dict{Channel, Vector{Union{Pulse, ZPulse}}}
end

convert{T<:Union{Pulse, ZPulse}}(::Type{PulseBlock}, p::T) = PulseBlock(Dict(p.channel => [p]))
PulseBlock{T<:Union{Pulse, ZPulse}}(p::T) = convert(PulseBlock, p)
PulseBlock(chans::Set{Channel}) = PulseBlock(Dict{Channel, Vector{Union{Pulse, ZPulse}}}(chan => Union{Pulse, ZPulse}[] for chan in chans))

promote_rule(::Type{Pulse}, ::Type{PulseBlock}) = PulseBlock
promote_rule(::Type{ZPulse}, ::Type{PulseBlock}) = PulseBlock
⊗(x::Pulse, y::Pulse) = ⊗(PulseBlock(x), PulseBlock(y))
⊗(x::Pulse, y::PulseBlock) = ⊗(PulseBlock(x), y)
⊗(x::PulseBlock, y::Pulse) = ⊗(x, PulseBlock(y))
⊗(x::ZPulse, y::ZPulse) = ⊗(PulseBlock(x), PulseBlock(y))
⊗(x::ZPulse, y::PulseBlock) = ⊗(PulseBlock(x), y)
⊗(x::PulseBlock, y::ZPulse) = ⊗(x, PulseBlock(y))
⊗(x::PulseBlock, y::PulseBlock) = PulseBlock(merge(x.pulses, y.pulses))

channels(pb::PulseBlock) = keys(pb.pulses)

function show(io::IO, pb::PulseBlock)
	strs = []
	for ps = values(pb.pulses)
		push!(strs, "(" * join([string(p) for p in ps], ", ") * ")")
	end
	str = join(strs, "⊗")
	print(io, "[$str]")
end

length(p::Pulse) = p.length
length(pb::PulseBlock) = maximum(sum(length(p) for p in ps) for ps in values(pb.pulses))

# TODO: make native and handle TA pairs
function waveform(p::Pulse, sampling_rate)
	# copy shape parameters from channel and convert to symbols to splat in call below
	shape_params = Dict(Symbol(k) => v for (k,v) in p.channel.shape_params)
	shape_params[:samplingRate] = sampling_rate
	shape_params[:length] = p.length
	return shape_params[:shapeFun](;shape_params...)
end

function MEAS(q::Qubit)
	m = measurement_channel(q)
	meas_pulse = Pulse("MEAS", m, m.shape_params["length"], m.shape_params["amp"], 0.0, m.shape_params["autodyne_freq"])
	pb = PulseBlock(meas_pulse)
	if m.trigger_channel != ""
		t = Marker(m.trigger_channel)
		trig_pulse = Pulse("TRIG", t, t.shape_params["length"], 1.0)
		pb = pb ⊗ trig_pulse
	end
	return pb
end
