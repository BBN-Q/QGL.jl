import Base.show

@enum CONTROL_OP WAIT SYNC LOAD_REPEAT REPEAT GOTO CALL RETURN

immutable ControlFlow
	label::AbstractString
	op::CONTROL_OP
	target
	value
end

export WAIT

wait() = ControlFlow("INIT", WAIT, 0, 0)

function show(io::IO, cf::ControlFlow)
	if cf.op == WAIT
		print(io, cf.label)
	end
end
