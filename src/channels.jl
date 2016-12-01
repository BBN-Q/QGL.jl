using PyCall
@pyimport QGL as pyQGL

import Base: show, ==, hash

export Qubit, Marker

abstract Channel
show(io::IO, c::Channel) = print(io, c.label)

immutable Qubit <: Channel
	label::String
	awg_channel::String
	gate_channel::String
	shape_params::Dict{Any,Any}
	frequency::Real
end

function Qubit(label)
	# for now pull from Python QGL
	# TODO: make native
	q = pyQGL.QubitFactory(label)
	phys_chan = typeof(q[:physChan]) == Void ? "" : q[:physChan][:label]
	gate_chan = typeof(q[:gateChan]) == Void ? "" : q[:gateChan][:label]
	Qubit(label, phys_chan, gate_chan, q[:pulseParams], q[:frequency])
end

immutable Marker <: Channel
	label::String
	awg_channel::String
	shape_params::Dict{Any, Any}
end

function Marker(label)
	# for now pull from Python QGL
	# TODO: make native
	m = pyQGL.ChannelLibrary[:channelLib][:channelDict][label]
	phys_chan = typeof(m[:physChan]) == Void ? "" : m[:physChan][:label]
	Marker(label, phys_chan, m[:pulseParams])
end

type QuadratureAWGChannel
	awg::String
	delay::Real
	mixer_correction::Matrix{Real}
end

==(a::Channel, b::Channel) = a.label == b.label
hash(c::Channel) = hash(c.label)
hash(c::Channel, h::UInt) = hash(c.label, h)

immutable Measurement <: Channel
	label::String
	awg_channel::String
	gate_channel::String
	trigger_channel::String
	shape_params::Dict{Any,Any}
	frequency::Real
end

function measurement_channel(q::Qubit)
	# look up measurement channel with convention of "M-q"
	m_label = "M-"*q.label
	m = pyQGL.ChannelLibrary[:channelLib][:channelDict][m_label]
	phys_chan = typeof(m[:physChan]) == Void ? "" : m[:physChan][:label]
	gate_chan = typeof(m[:gateChan]) == Void ? "" : m[:gateChan][:label]
	trig_chan = typeof(m[:trigChan]) == Void ? "" : m[:trigChan][:label]
	pulse_params = m[:pulseParams]
	pulse_params["autodyne_freq"]= m[:autodyneFreq]
	Measurement(m_label, phys_chan, gate_chan, trig_chan, pulse_params, m[:frequency])
end
