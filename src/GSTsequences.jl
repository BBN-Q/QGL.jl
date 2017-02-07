"""
Create a 1Q GST sequence for a csv file of single qubit Clifford numbers

create_1Q_GST_seqs(file, q; Id_length=50e-9, num_cals=500)

file	 : path to csv file
q		 : name of qubit in scope
Id_length : length of the Id pulse in seconds
num_cals	 : number of calibration sequences for 0 and 1

"""
function create_1Q_GST_seqs(file, q; Id_length=50e-9, num_cals=500)

	# create pulses once in a library
	m = MEAS(q)
	pulse_lib = [DiAC(q,x) for x in 1:24]
	insert!(pulse_lib, 1, QGL.PulseBlock(Id(q,Id_length)))

	seqs = Vector{Vector{QGL.SequenceEntry}}()
	f = open(file, "r")
	for ln in eachline(f)
		# convert from string to Int and 0-indexed to 1-indexed
		pulse_nums = map(x -> parse(Int, x) + 1, split(ln, ','))
		seq = Vector{QGL.SequenceEntry}(length(pulse_nums) + 1)
		map!(x -> pulse_lib[x], seq, pulse_nums)
		seq[end] = m
		push!(seqs, seq)
	end
	cals = cal_seqs((q,),num_repeats=num_cals)
	seqs = vcat(seqs, cals)
	return seqs
end
"""
Create a 1Q GST sequence for a csv file of single qubit Clifford numbers
using diatomic pulses

create_1Q_GST_seqs(file::Array{String,1}, q; Id_length=50e-9, num_cals=500)

file	 : a string array with the paths to multiple csv files
q		 : name of qubit in scope
Id_length : length of the Id pulse in seconds
num_cals	 : number of calibration sequences for 0 and 1
"""
function create_1Q_GST_seqs(file::Array{String, 1}, q; Id_length=50e-9,
	num_cals=500)

	# create pulses once in a library
	m = MEAS(q)
	pulse_lib = [DiAC(q,x) for x in 1:24]
	insert!(pulse_lib, 1, QGL.PulseBlock(Id(q,Id_length)))

	seqs = Vector{Vector{QGL.SequenceEntry}}()
	cals = cal_seqs((q,),num_repeats=num_cals)
	for fname in file
		f = open(fname, "r")
		for ln in eachline(f)
			# convert from string to Int and 0-indexed to 1-indexed
			pulse_nums = map(x -> parse(Int, x) + 1, split(ln, ','))
			seq = Vector{QGL.SequenceEntry}(length(pulse_nums) + 1)
			map!(x -> pulse_lib[x], seq, pulse_nums)
			seq[end] = m
			push!(seqs, seq)
		end
		seqs = vcat(seqs, cals)
	end
	return seqs
end
"""
Create a 1Q GST sequence for a csv file of single qubit Clifford numbers using
diatomic pulses.  The experimental sequence specified by the csv file is
repeated 10 times including cals.

create_1Q_GST10_seqs(file, q; Id_length=50e-9, num_cals=500)

file	 : path to csv file
q		 : name of qubit in scope
Id_length : length of the Id pulse in seconds
num_cals	 : number of calibration sequences for 0 and 1
"""
function create_1Q_GST10_seqs(file, q; Id_length=50e-9, num_cals=500)

	# create pulses once in a library
	m = MEAS(q)
	pulse_lib = [DiAC(q,x) for x in 1:24]
	insert!(pulse_lib, 1, QGL.PulseBlock(Id(q,Id_length)))
	seqs = Vector{Vector{QGL.SequenceEntry}}()
	f = open(file, "r")
	for ln in eachline(f)
		# convert from string to Int and 0-indexed to 1-indexed
		pulse_nums = map(x -> parse(Int, x) + 1, split(ln, ','))
		seq = Vector{QGL.SequenceEntry}(length(pulse_nums) + 1)
		map!(x -> pulse_lib[x], seq, pulse_nums)
		seq[end] = m
		push!(seqs, seq)
	end
	cals = cal_seqs((q,),num_repeats=num_cals)
	seqs = vcat(seqs, cals)

	# x10
	seqs = repeat(seqs, outer=[10])

	return seqs
end
