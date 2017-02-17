import Base.show

@enum CONTROL_OP WAIT SYNC LOAD_REPEAT REPEAT GOTO CALL RETURN

immutable ControlFlow
	label::String
	op::CONTROL_OP
	target
	value
end

wait() = ControlFlow("INIT", WAIT, 0, 0)
sync() = ControlFlow("SYNC", SYNC, 0, 0)
goto(target) = ControlFlow("GOTO", GOTO, target, 0)

function show(io::IO, cf::ControlFlow)
	print(io, cf.label)
	if cf.op == GOTO
		print(io, ": $(cf.target)")
	end
end
