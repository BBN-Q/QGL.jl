using PyCall
@pyimport QGL
@pyimport QGL.PatternUtils as QGL_PatternUtils

function compile_to_hardware(seqs, base_filename; suffix="")

	# save input code to file as metadata
	QGL.Compiler[:save_code](seqs, base_filename*suffix)

	# insert a WAIT at the beginning of every sequences
	wait_type = pytypeof(QGL.ControlFlow[:Wait]())
	for seq = seqs
		if !pyisinstance(seq[1], wait_type)
			insert!(seq, 1, QGL.ControlFlow[:Wait]())
		end
	end

	# Add the digitizer trigger to measurements
	QGL_PatternUtils.add_digitizer_trigger(seqs)

	# Add gating/blanking pulses
	QGL_PatternUtils.add_gate_pulses(seqs)

	# Add slave trigger
	QGL_PatternUtils.add_slave_trigger(seqs,
		QGL.ChannelLibrary[:channelLib][:channelDict]["slaveTrig"])

	# find channel set at top level to account for individual sequence channel variability
	channels = QGL.Compiler[:find_unique_channels](seqs[1])
	for seq = seqs[2:end]
		channels[:union](QGL.Compiler[:find_unique_channels](seq))
	end

	wire_seqs = QGL.Compiler[:compile_sequences](seqs, channels)

	# gating constraints
	logical_marker_chan_type = pytypeof(QGL.Channels[:LogicalMarkerChannel](label="dummy"))
	for (chan, seq) in wire_seqs
		if pyisinstance(chan, logical_marker_chan_type)
			wire_seqs[chan] = QGL_PatternUtils.apply_gating_constraints(chan[:physChan], seq)
		end
	end

	return wire_seqs, channels

end
