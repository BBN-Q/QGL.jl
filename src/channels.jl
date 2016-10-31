using PyCall
@pyimport QGL

import Base: show, ==, hash

abstract Channel
show(io::IO, c::Channel) = print(io, c.label)


immutable Qubit <: Channel
	label::AbstractString
	awg_channel::AbstractString
	gate_channel::AbstractString
	shape_params::Dict{Any,Any}
end

function Qubit(label)
	# for now pull from Python QGL
	# TODO: make native
	q = QGL.QubitFactory(label)
	phys_chan = typeof(q[:physChan]) == Void ? "" : q[:physChan][:label]
	gate_chan = typeof(q[:gateChan]) == Void ? "" : q[:gateChan][:label]
	Qubit(label, phys_chan, gate_chan, q[:pulseParams])
end

immutable Marker <: Channel
	label::AbstractString
	awg_channel::AbstractString
	shape_params::Dict{Any, Any}
end

function Marker(label)
	# for now pull from Python QGL
	# TODO: make native
	m = QGL.ChannelLibrary[:channelLib][:channelDict][label]
	phys_chan = typeof(m[:physChan]) == Void ? "" : m[:physChan][:label]
	Marker(label, phys_chan, m[:pulseParams])
end

type QuadratureAWGChannel
	awg::AbstractString
	delay::Real
	mixer_correction::Matrix{Real}
end

==(a::Channel, b::Channel) = a.label == b.label
hash(c::Channel) = hash(c.label)
