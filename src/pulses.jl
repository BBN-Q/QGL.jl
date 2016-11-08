import Base: convert, promote_rule, length

export X90, X, X90m, Y90, Y, Y90m, Z90, Z, Z90m, Id, ⊗

immutable Pulse
	label::String
	channel
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

Pulse(label, channel) = Pulse(label, channel, 0.0, 0.0, 0.0, 0.0)
Pulse(label, channel, length) = Pulse(label, channel, length, 0.0, 0.0, 0.0)
Pulse(label, channel, length, amp) = Pulse(label, channel, length, amp, 0.0, 0.0)
Pulse(label, channel, length, amp, phase) = Pulse(label, channel, length, amp, phase, 0.0)

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


type PulseBlock
	pulses::Dict{Channel, Vector{Union{Pulse, ZPulse}}}
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
