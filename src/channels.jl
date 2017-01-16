import JSON

import Base: show, ==, hash

export Qubit, Edge, Marker

global channel_json_file
let cfg_folder = joinpath(Pkg.dir("QGL"), "cfg"), cfg_file = joinpath(cfg_folder, "cfg.json")
	if isdir(cfg_folder) && isfile(cfg_file)
		global channel_json_file = JSON.parsefile(cfg_file)["channel_params_file"]
	else
		println("Please provide path to channel parameters JSON file:")
		path = chomp(readline())
		if !isdir(cfg_folder)
			mkdir(cfg_folder)
		end
		open(cfg_file, "w") do f
			JSON.print(f, Dict{String,String}("channel_params_file" => path))
		end
	end
end

# TODO: is this useful or perhaps all we can do with immutable channel objects
# watch the channel JSON file
# @async begin
# 	while true
# 		event = watch_file("/home/cryan/Programming/Repos/PyQLab/cfg/ChannelParams.json")
# 		if event.changed
# 			warn("ChannelParams file updated.")
# 	end
# end


abstract Channel
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
	channel_params = JSON.parsefile(channel_json_file)["channelDict"]

	if label in keys(channel_params)
		q_params = channel_params[label]
		phys_chan = get(q_params, "physChan", "")
		gate_chan = get(q_params, "gateChan", "")

		# pull out shape_params and convert keys to symbols for splatting into shape function
		shape_params = Dict{Symbol, Any}(Symbol(k) => v for (k,v) in q_params["pulseParams"])

		# translate pulse function in shape params from a string to a function handle and snakeify key
		shape_params[:shape_function] = getfield(QGL.PulseShapes, Symbol(pop!(shape_params, :shapeFun)))

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
Channel represeting a digital output marker line.
"""
immutable Marker <: Channel
	label::String
	awg_channel::String
	shape_params::Dict{Any, Any}
end

function Marker(label)
	m_params = JSON.parsefile(channel_json_file)["channelDict"][label]
	phys_chan = get(m_params, "physChan", "")
	# translate pulse function in shape params from a string to a function handle and snakeify key
	shape_params =  Dict{Symbol, Any}(Symbol(k) => v for (k,v) in m_params["pulseParams"])
	shape_params[:shape_function] = getfield(QGL.PulseShapes,  Symbol(pop!(shape_params, :shapeFun)))
	Marker(label, phys_chan, shape_params)
end

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
	measurement_channel(q::Qubit)

Looks us the measurement channel associated with qubit. Currently uses the
M-q.label convention.
"""
function measurement_channel(q::Qubit)
	m_label = "M-"*q.label
	m_params = JSON.parsefile(channel_json_file)["channelDict"][m_label]
	phys_chan = get(m_params, "physChan", "")
	gate_chan = get(m_params, "gateChan", "")
	trig_chan = get(m_params, "trigChan", "")
	# pull out shape_params and convert keys to symbols for splatting into shape function
	shape_params = Dict{Symbol, Any}(Symbol(k) => v for (k,v) in m_params["pulseParams"])
	# translate pulse function in shape params from a string to a function handle and snakeify key
	shape_params[:shape_function] = getfield(QGL.PulseShapes,  Symbol(pop!(shape_params, :shapeFun)))
	# inject autodyne frequence into the `shape_params` where it should be
	shape_params[:autodyne_freq] = m_params["autodyneFreq"]
	Measurement(m_label, phys_chan, gate_chan, trig_chan, shape_params, m_params["frequency"])
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
	channel_params = JSON.parsefile(channel_json_file)["channelDict"]

	edges = filter(
		(k,v) -> get(v, "x__class__", "") == "Edge" && v["source"] == source.label && v["target"] == target.label,
		channel_params)

	@assert length(edges) == 1 "Found $(length(edges)) matching edges for $source → $target"

	e_params = collect(values(edges))[1]

	phys_chan = get(e_params, "physChan", "")
	gate_chan = get(e_params, "gateChan", "")

	# pull out shape_params and convert keys to symbols for splatting into shape function
	shape_params = e_params["pulseParams"]
	shape_params = Dict{Symbol, Any}(Symbol(k) => v for (k,v) in shape_params)

	# translate pulse function in shape params from a string to a function handle and snakeify key
	shape_params[:shape_function] = getfield(QGL.PulseShapes, Symbol(pop!(shape_params, :shapeFun)))

	Edge(e_params["label"], source, target, phys_chan, gate_chan, shape_params, e_params["frequency"])
end
