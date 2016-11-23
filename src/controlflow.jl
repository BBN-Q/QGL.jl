import Base.show

@enum CONTROL_OP WAIT SYNC LOAD_REPEAT REPEAT GOTO CALL RETURN

immutable ControlFlow
	label::AbstractString
	op::CONTROL_OP
	target
	value
end

wait() = ControlFlow("INIT", WAIT, 0, 0)
sync() = ControlFlow("SYNC", SYNC, 0, 0)
goto(target) = ControlFlow("GOTO", GOTO, target, 0)

function show(io::IO, cf::ControlFlow)
	if cf.op == WAIT
		print(io, cf.label)
	end
end
