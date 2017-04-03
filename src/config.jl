# load JSON configuration files for channel and instrument parameters
#
# Copyright 2017 Raytheon BBN Technologies

module config

import JSON

channel_json_file = ""
instrument_json_file = ""
sequence_files_path = ""

cfg_folder = joinpath(Pkg.dir("QGL"), "cfg")
cfg_file = joinpath(cfg_folder, "cfg.json")

if isdir(cfg_folder) && isfile(cfg_file)
	cfg = JSON.parsefile(cfg_file)
	channel_json_file = get(cfg, "channel_params_file", "")
	instrument_json_file = get(cfg, "instrument_params_file", "")
	sequence_files_path = get(cfg, "sequence_files_path", "")
else
	println("Please provide path to channel parameters JSON file:")
	channel_json_file = chomp(readline())
	println("Please provide path to instrument parameters JSON file:")
	instrument_json_file = chomp(readline())
	println("Please provide path to where sequence files should be output to:")
	sequence_files_path = chomp(readline())

	if !isdir(cfg_folder)
		mkdir(cfg_folder)
	end
	open(cfg_file, "w") do f
		JSON.print(f,
			Dict{String,String}(
				"channel_params_file" => channel_json_file,
				"instrument_params_file" => instrument_json_file,
				"sequence_files_path" => sequence_files_path
			)
		)
	end
end

get_channel_params() = JSON.parsefile(channel_json_file)["channelDict"]
get_instrument_params() = JSON.parsefile(instrument_json_file)["instrDict"]

# TODO: is this useful or perhaps all we can do with immutable channel objects
# watch the channel JSON file
# @async begin
# 	while true
# 		event = watch_file("/home/cryan/Programming/Repos/PyQLab/cfg/ChannelParams.json")
# 		if event.changed
# 			warn("ChannelParams file updated.")
# 	end
# end

end
