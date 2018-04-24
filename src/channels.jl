import Base: show, ==, hash

export Qubit, Edge, Marker

import .config.get_qubit_params
import .config.get_marker_params
import .config.get_edge_params
import .config.get_instrument_params

@compat abstract type Channel end
show(io::IO, c::Channel) = print(io, c.label)

# TODO: is there a benefit to having the concrete channel types immutable?
"""
Channel representing single qubit drive.
"""
immutable Qubit <: Channel
	label::String
	awg_channel::String
	gate_channel::String
	shape_params::Dict{Symbol,Any}
	frequency::Float64
end

function Qubit(label)
	channel_params = get_qubit_params()

	if label in keys(channel_params)
		q_params = channel_params[label]["control"]
		phys_chan = get(q_params, "AWG", "")
		gate_chan = get(q_params, "gate", "")

		# pull out shape_params and convert keys to symbols for splatting into shape function
		shape_params = Dict{Symbol, Any}(Symbol(k) => v for (k,v) in q_params["pulse_params"])

		# translate pulse function in shape params from a string to a function handle and snakeify key
		shape_params[:shape_function] = getfield(QGL.PulseShapes, Symbol(pop!(shape_params, :shape_fun)))

		# snakeify some other parameters
		if :dragScaling in keys(shape_params)
			shape_params[:drag_scaling] = pop!(shape_params, :dragScaling)
		end

		Qubit(label, phys_chan, gate_chan, shape_params, q_params["frequency"])
	else
		warn("Unable to find Qubit label $label in channel json file. Creating default Qubit channel")
		Qubit(label,"", "", Dict{String,Any}(), 0.0)
	end

end

"""
Channel representing a digital output marker line.
"""
immutable Marker <: Channel
	label::String
	awg_channel::String
	shape_params::Dict{Any, Any}
end

function Marker(label)
	phys_chan = get_marker_params()[label]
	m_params = get_instrument_params()[split(phys_chan)[1]]["markers"][split(phys_chan)[2]]
	# translate pulse function in shape params from a string to a function handle and snakeify key
	shape_params =  Dict{Symbol, Any}(Symbol(k) => v for (k,v) in m_params)
	shape_params[:shape_function] = getfield(QGL.PulseShapes,  Symbol(pop!(shape_params, :shape_fun)))
	Marker(label, phys_chan, shape_params)
end

# NOTE is this mutable on purpose??
type QuadratureAWGChannel
	awg::String
	delay::Real
	mixer_correction::Matrix{Real}
end

==(a::Channel, b::Channel) = a.label == b.label
hash(c::Channel, h::UInt) = hash(c.label, h)


"""
Channel representing qubit measurement drive
"""
immutable Measurement <: Channel
	label::String
	awg_channel::String
	gate_channel::String
	trigger_channel::String
	shape_params::Dict{Any,Any}
	frequency::Real
end

"""
	measurement_channel(l:String)

Looks us the measurement channel associated with qubit.
"""
function measurement_channel(l::String)
	m_params = get_qubit_params()[l]["measure"]
	phys_chan = get(m_params, "AWG", "")
	gate_chan = get(m_params, "gate", "")
	trig_chan = get(m_params, "trigger", "")
	# pull out shape_params and convert keys to symbols for splatting into shape function
	shape_params = Dict{Symbol, Any}(Symbol(k) => v for (k,v) in m_params["pulse_params"])
	# translate pulse function in shape params from a string to a function handle and snakeify key
	shape_params[:shape_function] = getfield(QGL.PulseShapes,  Symbol(pop!(shape_params, :shape_fun)))
	# inject autodyne frequence into the `shape_params` where it should be
	shape_params[:autodyne_freq] = m_params["autodyne_freq"]
	Measurement(string("M-", l), phys_chan, gate_chan, trig_chan, shape_params, 0)
end

"""
Channel representing an interaction drive.
"""
immutable Edge <: Channel
	label::String
	source::Qubit
	target::Qubit
	awg_channel::String
	gate_channel::String
	shape_params::Dict{Symbol,Any}
	frequency::Float64
end

"""
	Edge(source::Qubit, target::Qubit)

Create the edge representing interaction drive from `source` to `target`.
"""
function Edge(source::Qubit, target::Qubit)
	# look up whether we have an edge connecting source -> target
	channel_params = get_edge_params()

	edges = filter(
		(k,v) -> v["source"] == source.label && v["target"] == target.label,
		channel_params)

	@assert length(edges) == 1 "Found $(length(edges)) matching edges for $source → $target"

	e_params = collect(values(edges))[1]

	phys_chan = get(e_params, "AWG", "")
	gate_chan = get(e_params, "gate", "")

	# pull out shape_params and convert keys to symbols for splatting into shape function
	shape_params = e_params["pulse_params"]
	shape_params = Dict{Symbol, Any}(Symbol(k) => v for (k,v) in shape_params)

	# translate pulse function in shape params from a string to a function handle and snakeify key
	shape_params[:shape_function] = getfield(QGL.PulseShapes, Symbol(pop!(shape_params, :shape_fun)))

	Edge(collect(keys(edges))[1], source, target, phys_chan, gate_chan, shape_params, e_params["frequency"])
end
