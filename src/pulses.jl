import Base: convert, promote_rule, length, ==

export X90, X, X90m, Y90, Y, Y90m, U90, Uθ, Z90, Z, Z90m, Id, ⊗, MEAS, AC, DiAC, ZX90

immutable Pulse
	label::String
	channel::Channel
	length::Float64
	amp::Float64
	phase::Float64
	frequency::Float64
	shapeFun::PyObject
	hash::UInt
end

_hash(p::Pulse) =
	hash(p.label,
	hash(p.channel,
	hash(p.length,
	hash(p.amp,
	hash(p.phase,
	hash(p.frequency,
	hash(p.shapeFun)))))))

function Pulse(label::String, channel::Channel, length::Real=0.0, amp::Real=0.0, phase::Real=0.0, frequency::Real=0.0, shapeFun::PyObject=channel.shape_params["shapeFun"])
	# precompute pulse has we'll call it for each pulse we compile
	pulse_hash = hash(label, hash(channel, hash(length, hash(amp, hash(phase, hash(frequency, hash(shapeFun)))))))
	Pulse(label, channel, Float64(length), Float64(amp), Float64(phase), Float64(frequency), shapeFun, pulse_hash)
end

==(a::Pulse, b::Pulse) = a.hash == b.hash
hash(p::Pulse, h::UInt) = hash(p.hash, h)

show(io::IO, p::Pulse) = print(io, "$(p.label)($(p.channel.label))")

immutable ZPulse
	label::String
	channel::Channel
	angle::Float64
end


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

U90(q::Qubit, phase::Float64 = 0.0) = Pulse("U90", q, q.shape_params["length"], 0.25, phase, 0)
Uθ(q::Union{Qubit, Edge}, angle::Float64, phase::Float64) = Pulse("Uθ", q, q.shape_params["length"], angle, phase, 0)
Uθ(q::Union{Qubit, Edge}, angle::Float64, phase::Float64, shape::String) = Pulse("Uθ", q, q.shape_params["length"], angle, phase, 0, pyQGL.PulseShapes[Symbol(shape)])
Uθ(q::Union{Qubit, Edge}, length::Float64, angle::Float64, phase::Float64, shape::String) = Pulse("Uθ", q, length, angle, phase, 0, pyQGL.PulseShapes[Symbol(shape)])

Z(q::Union{Qubit, Edge}, angle=0.5) = ZPulse("Z", q, angle)
Z90(q::Union{Qubit, Edge}) = ZPulse("Z90", q, 0.25)
Z90m(q::Union{Qubit, Edge}) = ZPulse("Z90m", q, 0.75)
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
PulseBlock{T<:Channel}(chans::Set{T}) = PulseBlock(Dict{Channel, Vector{Union{Pulse, ZPulse}}}(chan => Union{Pulse, ZPulse}[] for chan in chans))
PulseBlock{T<:Channel}(chans::Vector{T}) = PulseBlock(Dict{Channel, Vector{Union{Pulse, ZPulse}}}(chan => Union{Pulse, ZPulse}[] for chan in chans))

promote_rule(::Type{Pulse}, ::Type{PulseBlock}) = PulseBlock
promote_rule(::Type{ZPulse}, ::Type{PulseBlock}) = PulseBlock
⊗(x::Pulse, y::Pulse) = ⊗(PulseBlock(x), PulseBlock(y))
⊗(x::Pulse, y::PulseBlock) = ⊗(PulseBlock(x), y)
⊗(x::PulseBlock, y::Pulse) = ⊗(x, PulseBlock(y))
⊗(x::ZPulse, y::ZPulse) = ⊗(PulseBlock(x), PulseBlock(y))
⊗(x::ZPulse, y::PulseBlock) = ⊗(PulseBlock(x), y)
⊗(x::PulseBlock, y::ZPulse) = ⊗(x, PulseBlock(y))
⊗(x::Pulse, y::ZPulse) = ⊗(PulseBlock(x), PulseBlock(y))
⊗(x::PulseBlock, y::PulseBlock) = PulseBlock(merge(x.pulses, y.pulses))

channels(pb::PulseBlock) = keys(pb.pulses)

function show(io::IO, pb::PulseBlock)
	strs = []
	for ps = values(pb.pulses)
		if length(ps) > 0
			push!(strs, "(" * join([string(p) for p in ps], ", ") * ")")
		end
	end
	str = join(strs, "⊗")
	print(io, str)
end

length(p::Pulse) = p.length
length(pb::PulseBlock) = maximum(sum(length(p) for p in ps) for ps in values(pb.pulses))

# TODO: make native and handle TA pairs
function waveform(p::Pulse, sampling_rate)
	# copy shape parameters from channel and convert to symbols to splat in call below
	shape_params = Dict(Symbol(k) => v for (k,v) in p.channel.shape_params)
	shape_params[:samplingRate] = sampling_rate
	shape_params[:length] = p.length
	shape_params[:shapeFun] = p.shapeFun
	# amplitude and phase will be applied later in translators
	delete!(shape_params, :amp)
	delete!(shape_params, :phase)
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

function flat_top_gaussian(chan; pi_shift = false)
	return [Uθ(chan, chan.shape_params["riseFall"], chan.shape_params["amp"], chan.shape_params["phase"]/2π + 0.5*pi_shift, "gaussOn"),
	Uθ(chan, chan.shape_params["length"], chan.shape_params["amp"], chan.shape_params["phase"]/2π + 0.5*pi_shift, "constant"),
	Uθ(chan, chan.shape_params["riseFall"], chan.shape_params["amp"], chan.shape_params["phase"]/2π + 0.5*pi_shift, "gaussOff")]
end

function ZX90(qc::Qubit, qt::Qubit)
	CRchan = Edge(qc,qt)
  return PulseBlock(Dict(CRchan => vcat(flat_top_gaussian(CRchan), [Id(CRchan, qc.shape_params["length"])], flat_top_gaussian(CRchan; pi_shift = true), [Id(CRchan, qc.shape_params["length"])]), qc => [Id(qc, CRchan.shape_params["length"]+2*CRchan.shape_params["riseFall"]), X(qc), Id(qc, CRchan.shape_params["length"]+2*CRchan.shape_params["riseFall"]), X(qc)]))
end
