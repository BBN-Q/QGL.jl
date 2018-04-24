# load JSON configuration files for channel and instrument parameters
#
# Copyright 2017 Raytheon BBN Technologies

module config

import YAML

cfg_folder = joinpath(Pkg.dir("QGL"), "cfg")
cfg_path = joinpath(cfg_folder, "cfg_path.txt")
# for simplicity here use single config file

if isdir(cfg_folder) && isfile(cfg_path)
    f = open(cfg_path)
    cfg_yaml = readstring(f)
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

cfg = YAML.load_file(cfg_yaml)
get_qubit_params() = cfg["qubits"]
get_marker_params() = cfg["markers"]
get_edge_params() = cfg["edges"]
get_instrument_params() = cfg["instruments"]

end
