import Base: convert, promote_rule, length, ==

export X90, X, X90m, Y90, Y, Y90m, U90, Uθ, Z90, Z, Z90m, Id, ⊗, MEAS, AC, DiAC, ZX90

# NOTE A suggested type hierarchy:
# abstract AbstractBlock
#   - abstract AbstractPulse
#       * immutable Pulse
#       * immutable ZPulse
#   - type PulseBlock
@compat abstract type AbstractPulse end

immutable Pulse <: AbstractPulse
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
	kwargs = Base.kwarg_decl(m, typeof(ml.mt.kwsorter))

	filter!((k,v) -> k == :shape_function || k in kwargs, shape_params)

	# precompute pulse hash we'll evaluate it for each pulse we compile
	pulse_hash = hash((label, chan, length, amp, phase, frequency, shape_params))
	Pulse(label, chan, length, amp, phase, frequency, shape_params, pulse_hash)
end

==(a::Pulse, b::Pulse) = a.hash == b.hash
hash(p::Pulse, h::UInt) = hash(p.hash, h)

show(io::IO, p::Pulse) = print(io, "$(p.label)($(p.channel.label))")

immutable ZPulse <: AbstractPulse
	label::String
	channel::Channel
	angle::Float64
end

show(io::IO, z::ZPulse) = print(io, "$(z.label)($(z.channel.label), $(z.angle))")

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

U90(q::Qubit, phase::Float64=0.0) = Pulse("U90", q, q.shape_params[:length], q.shape_params[:pi2Amp], phase, 0)
U180(q::Qubit, phase::Float64=0.0) = Pulse("U180", q, q.shape_params[:length], q.shape_params[:piAmp], phase, 0)
Uθ(q::Union{Qubit, Edge}, length, amp, phase) = Pulse("Uθ", q, length, amp, phase)
Uθ(q::Union{Qubit, Edge}, length, amp, phase, freq, shape_params) = Pulse("Uθ", q, length, amp, phase, freq, shape_params)

Z(q::Union{Qubit, Edge}, angle=0.5) = ZPulse("Z", q, angle)
Z90(q::Union{Qubit, Edge}) = ZPulse("Z90", q, 0.25)
Z90m(q::Union{Qubit, Edge}) = ZPulse("Z90m", q, 0.75)
length(z::ZPulse) = 0

function Id(c::Channel, length)
	# TODO: inject constant pulse shape
	Pulse("Id", c, length, 0.0)
end
Id(c::Channel) = Id(c, c.shape_params[:length])

"""
	AC(q::Qubit, num; sampling_rate=1.2e9)

Atomic Clifford `num` on a single qubit `q`. AC pulses are enumerated 0:24.
"""
function AC(q::Qubit, num; sampling_rate=1.2e9)
	if 0 < num < 10
		pulses = [
			Id,
			X90,
			X,
			X90m,
			Y90,
			Y,
			Y90m,
			Z90,
			Z,
			Z90m,
		]
		return pulses[num](q)
	elseif num == 11
		return U180(q, 1/8);
	elseif num == 12
		return U180(q, -1/8)
	elseif num <= 24
		# figure out the approximate nutation frequency calibration from the X180
		# and the sampling_rate.  This isn't ideal as it breaks the split between
		# the pulse and the hardware representation
		Xp = X(q)
		xpulse = waveform(Xp, sampling_rate)
		nut_freq = 0.5/sum(xpulse)*sampling_rate

		rot_angle = [fill(0.5, 4); fill(1/3, 8)]

		# rotation axis polar angle in portions of circle
		# comes in three flavours: x+z or y+z, xy+z and xy-z
		xz = 1/8
		xyzₚ = acos(1/√3) / 2π
		xyzₘ = (π - acos(1/√3) ) / 2π
		Θ = [xz, xz, xz, xz, xyzₚ, xyzₘ, xyzₚ, xyzₘ, xyzₘ, xyzₚ, xyzₚ, xyzₘ]
		# rotation axis azimuthal angle in portions of circle
		ϕ = [0, 1/2, 1/4, -1/4, 1/4, 5/8, -1/8, 3/8, 1/8, 5/8, 3/8, -1/8]

		#TODO: reduce code duplication with pulseshapes.jl
		if q.shape_params[:length] > 0
			# start from a gaussian shaped pulse
			gauss_pulse = PulseShapes.gaussian(pulse_length=q.shape_params[:length], sampling_rate=sampling_rate)
			# scale to achieve to the desired rotation
			cal_scale = (rot_angle/2/pi)*sampling_rate/sum(gauss_pulse)
			# calculate the phase ramp steps to achieve the desired Z component to the rotation axis
			phase_steps = -2π*cos(Θ)*cal_scale*gauss_pulse/sampling_rate
			# Calculate Z DRAG correction to phase steps
			# β is a conversion between XY drag scaling and Z drag scaling
			β = q.shape_params[:drag_scaling]/sampling_rate
			instantaneous_detuning = β * (2π*cal_scale*sin(Θ)*gauss_pulse).^2
			phase_steps += instantaneous_detuning*(1/sampling_rate)
			frame_change = sum(phase_steps)
		elseif abs(Θ) <1e-10
			# Otherwise assume we have a zero-length Z rotation
			frame_change = -rot_angle
		end

		return PulseBlock(Dict(q => [Pulse("AC", q, q.shape_params[:length], 1.0,
		             ϕ[num-12], q.frequency,
		             Dict(:shape_function => getfield(QGL.PulseShapes, :arb_axis_drag),
		                  :nut_freq => nut_freq,
		                  :rot_angle => rot_angle[num-12],
		                  :Θ => Θ[num-12])), Z(q, frame_change)]))
	else
		error("Invalid single qubit Atomic Clifford number")
	end

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
	pulses::Dict{Channel, Vector{AbstractPulse}}
end

convert(::Type{PulseBlock}, p::AbstractPulse) = PulseBlock(Dict(p.channel => [p]))
PulseBlock(p::AbstractPulse) = convert(PulseBlock, p)
PulseBlock{T<:Channel}(chans::Set{T}) = PulseBlock(Dict(chan => AbstractPulse[] for chan in chans))
PulseBlock{T<:Channel}(chans::Vector{T}) = PulseBlock(Dict(chan => AbstractPulse[] for chan in chans))

promote_rule{T<:AbstractPulse}(::Type{T}, ::Type{PulseBlock}) = PulseBlock

⊗(x::AbstractPulse, y::AbstractPulse) = PulseBlock(x) ⊗ PulseBlock(y)
⊗(x::PulseBlock, y::PulseBlock) = PulseBlock(merge(x.pulses, y.pulses))
⊗(x::AbstractPulse, y::PulseBlock) = ⊗(promote(x,y)...)
⊗(x::PulseBlock, y::AbstractPulse) = ⊗(promote(x,y)...)

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
