"""
Create a 1Q GST sequence for a csv file of single qubit Clifford numbers
"""
function create_1Q_GST_seqs(file, q)

	# create pulses once in a library
	m = MEAS(q)
	pulse_lib = [DiAC(q,x) for x in 1:24]
	insert!(pulse_lib, 1, QGL.PulseBlock(Id(q,0)))

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
	return seqs
end
