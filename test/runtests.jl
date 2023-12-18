# setup cfg to point to test channel parameters JSON file
import YAML
cfg_folder = joinpath(dirname(@__FILE__), "..", "cfg")
cfg_file = joinpath(cfg_folder, "cfg_path.txt")

# backup existing one
restore_backup = false
if isfile(cfg_file)
	cp(cfg_file, cfg_file*".orig", force=true)
	restore_backup = true
end
if !isdir(cfg_folder)
	mkdir(cfg_folder)
end

open(cfg_file, "w") do f
	write(f, joinpath(cfg_folder, "test_measure.yml"))
end
# 	cfg = Dict{String,String}()
# 	cfg["channel_params_file"] = joinpath(dirname(@__FILE__), "ChannelParams.json")
# 	cfg["instrument_params_file"] = joinpath(dirname(@__FILE__), "Instruments.json")
# 	cfg["sequence_files_path"] = sequence_files_path
# 	JSON.print(f, cfg)
# end

using QGL
using Test

try
@testset "Qubits" begin
q1 = Qubit("q1")
@test q1.label == "q1"
end

@testset "Pulse Creation" begin
q1 = Qubit("q1")
p = X90(q1)
@test p.label == "X90"
end

finally
if restore_backup
	mv(cfg_file*".orig", cfg_file, force=true)
end

end
