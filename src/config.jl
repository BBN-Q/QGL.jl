# load JSON configuration files for channel and instrument parameters
#
# Copyright 2017 Raytheon BBN Technologies

module config
import ..yaml

using Pkg
#import .yaml.load_file_relative

cfg_folder = joinpath(@__DIR__, "..", "cfg")
cfg_path = joinpath(cfg_folder, "cfg_path.txt")
# for simplicity here use single config file

if isdir(cfg_folder) && isfile(cfg_path)
    f = open(cfg_path)
    cfg_yaml = read(f, String)
    close(f)

else
	println("Please provide path to yaml settings file:")
	cfg_yaml = chomp(readline())

	if !isdir(cfg_folder)
		mkdir(cfg_folder)
	end
	open(cfg_path, "w") do f
        write(f, cfg_yaml)
    end
end

cfg = yaml.load_file_relative(cfg_yaml)
get_qubit_params() = cfg["qubits"]
get_marker_params() = cfg["markers"]
get_edge_params() = cfg["edges"]
get_instrument_params() = cfg["instruments"]
sequence_files_path = cfg["config"]["AWGDir"]

end
