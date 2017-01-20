# setup cfg to point to test channel parameters JSON file
import JSON
cfg_folder = joinpath(dirname(@__FILE__), "..", "cfg")
cfg_file = joinpath(cfg_folder, "cfg.json")
# backup existing one
restore_backup = false
if isfile(cfg_file)
	cp(cfg_file, cfg_file*".orig")
	restore_backup = true
end
if !isdir(cfg_folder)
	mkdir(cfg_folder)
end
open(cfg_file, "w") do f
	JSON.print(f, Dict{String,String}("channel_params_file" => joinpath(dirname(@__FILE__), "ChannelParams.json")))
end

using QGL
using Base.Test

try
@testset "Pulse Creation" begin
p = X90(q1)
@test p.label = "X90"
end

finally
if restore_backup
	mv(cfg_file*".orig", cfg_file, remove_destination=true)
end

end
