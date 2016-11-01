immutable ControlFlow
	label::AbstractString
end

export WAIT

WAIT() = ControlFlow("WAIT")
