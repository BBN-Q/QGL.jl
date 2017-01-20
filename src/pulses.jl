import Base: convert, promote_rule, length, ==

export X90, X, X90m, Y90, Y, Y90m, U90, Uθ, Z90, Z, Z90m, Id, ⊗, MEAS, AC, DiAC, ZX90

immutable Pulse
	label::String
	channel::Channel
	length::Float64
	amp::Float64
	phase::Float64
	frequency::Float64
	shape_params::Dict{Symbol, Any}
	hash::UInt
end

function Pulse(
		label::String,
		chan::Channel,
		length::Real=0.0,
		amp::Real=0.0,
		phase::Real=0.0,
		frequency::Real=0.0,
		shape_params=Dict{Symbol,Any}())

	# override the default channel parameters with any passed in
	shape_params = merge(chan.shape_params, shape_params)

	# amplitude and phase will be applied later in translators
	delete!(shape_params, :amp)
	delete!(shape_params, :phase)

	# detemine the necessary parameters
	# WARNING! this is obviously subject to change in Julia Base
	ml = methods(shape_params[:shape_function])
	m = collect(ml)[1]
	kwargs = Base.kwarg_decl(m.sig, typeof(ml.mt.kwsorter))

	filter!((k,v) -> k == :shape_function || k in kwargs, shape_params)

	# precompute pulse hash we'll evaluate it for each pulse we compile
	pulse_hash = hash(label, hash(chan, hash(length, hash(amp, hash(phase, hash(frequency, hash(shape_params)))))))
	Pulse(label, chan, Float64(length), Float64(amp), Float64(phase), Float64(frequency), shape_params, pulse_hash)
end

==(a::Pulse, b::Pulse) = a.hash == b.hash
hash(p::Pulse, h::UInt) = hash(p.hash, h)

show(io::IO, p::Pulse) = print(io, "$(p.label)($(p.channel.label))")

immutable ZPulse
	label::String
	channel::Channel
	angle::Float64
end

# loop through and eval to  create some basic 90/180 pulses
# quote the pi2Amp/piAmp symbols to interpolate the symbol
for (func, label, amp, phase) in [
	(:X90,  "X90",  :(:pi2Amp), 0),
	(:X,    "X",    :(:piAmp),  0),
	(:X90m, "X90m", :(:pi2Amp), 0.5),
	(:Y90,  "Y90",  :(:pi2Amp), 0.25),
	(:Y,    "Y",    :(:piAmp),  0.25),
	(:Y90m, "Y90m", :(:pi2Amp), 0.75)
	]
	@eval $func(q) = Pulse($label, q, q.shape_params[:length], q.shape_params[$amp], $phase, 0)
end

U90(q::Qubit, phase::Float64=0.0) = Pulse("U90", q, q.shape_params[:length], 0.25, phase, 0)
Uθ(q::Union{Qubit, Edge}, length, amp, phase) = Pulse("Uθ", q, length, amp, phase)
Uθ(q::Union{Qubit, Edge}, length, amp, phase, freq, shape_params) = Pulse("Uθ", q, length, amp, phase, freq, shape_params)

Z(q::Union{Qubit, Edge}, angle=0.5) = ZPulse("Z", q, angle)
Z90(q::Union{Qubit, Edge}) = ZPulse("Z90", q, 0.25)
Z90m(q::Union{Qubit, Edge}) = ZPulse("Z90m", q, 0.75)
length(z::ZPulse) = 0

show(io::IO, z::ZPulse) = print(io, "$(z.label)($(z.channel.label), $(z.angle))")

function Id(c::Channel, length)
	# TODO: inject constant pulse shape
	Pulse("Id", c, length, 0.0)
end
Id(c::Channel) = Id(c, c.shape_params[:length])


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

"""
	waveform(p::Pulse, sampling_rate)

Render a waveform for a pulse at a given sampling rate.
"""
function waveform(p::Pulse, sampling_rate)
	params = copy(p.shape_params)
	shape_function = pop!(params, :shape_function)
	return shape_function(;pulse_length=p.length, sampling_rate=sampling_rate, params...)
end

function MEAS(q::Qubit)
	m = measurement_channel(q)
	meas_pulse = Pulse("MEAS", m, m.shape_params[:length], m.shape_params[:amp], 0.0, m.shape_params[:autodyne_freq])
	pb = PulseBlock(meas_pulse)
	if m.trigger_channel != ""
		t = Marker(m.trigger_channel)
		trig_pulse = Pulse("TRIG", t, t.shape_params[:length], 1.0)
		pb = pb ⊗ trig_pulse
	end
	return pb
end

"""
	flat_top_gaussian(chan; pi_shift=false)

Helper function that returns an Array of pulses to implement a flat-topped gaussian pulse.
"""
function flat_top_gaussian(chan; pi_shift=false)
	pulse_phase = chan.shape_params[:phase]/2π + 0.5*pi_shift
	pulse_amp = chan.shape_params[:amp]
	return [
		Uθ(chan, chan.shape_params[:riseFall], pulse_amp, pulse_phase, 0.0,
			Dict(:shape_function => getfield(QGL.PulseShapes, :half_gaussian), :direction => QGL.PulseShapes.HALF_GAUSSIAN_RISE)),
		Uθ(chan, chan.shape_params[:length], pulse_amp, pulse_phase, 0.0, Dict(:shape_function => getfield(QGL.PulseShapes, :constant))),
		Uθ(chan, chan.shape_params[:riseFall], pulse_amp, pulse_phase, 0.0,
			Dict(:shape_function => getfield(QGL.PulseShapes, :half_gaussian), :direction => QGL.PulseShapes.HALF_GAUSSIAN_FALL))
	]
end

"""
	ZX90(qc::Qubit, qt::Qubit)

Implements an echoed ZX90 "cross-resonance" gate.
"""
function ZX90(qc::Qubit, qt::Qubit)
	CRchan = Edge(qc,qt)
	flat_top_length = CRchan.shape_params[:length] + 2*CRchan.shape_params[:riseFall]
  return PulseBlock( Dict(
		CRchan => [flat_top_gaussian(CRchan); Id(CRchan, qc.shape_params[:length]); flat_top_gaussian(CRchan; pi_shift=true); Id(CRchan, qc.shape_params[:length])],
		qc => [Id(qc, flat_top_length), X(qc), Id(qc, flat_top_length), X(qc)]
	))
end
