# setup cfg to point to test channel parameters JSON file
import YAML
# cfg_folder = joinpath(dirname(@__FILE__), "..", "cfg")
# cfg_file = joinpath(cfg_folder, "measure.yml")
# backup existing one
# restore_backup = false
# if isfile(cfg_file)
# 	cp(cfg_file, cfg_file*".orig")
# 	restore_backup = true
# end
# if !isdir(cfg_folder)
# 	mkdir(cfg_folder)
# end

# sequence_files_path = joinpath(dirname(@__FILE__), "sequence_files")
# if !isdir(sequence_files_path)
# 	mkdir(sequence_files_path)
# end
# open(cfg_file, "w") do f
# 	cfg = Dict{String,String}()
# 	cfg["channel_params_file"] = joinpath(dirname(@__FILE__), "ChannelParams.json")
# 	cfg["instrument_params_file"] = joinpath(dirname(@__FILE__), "Instruments.json")
# 	cfg["sequence_files_path"] = sequence_files_path
# 	JSON.print(f, cfg)
# end

using QGL
using Base.Test

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
	mv(cfg_file*".orig", cfg_file, remove_destination=true)
end

end
