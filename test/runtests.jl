io = IOBuffer(joinpath(@__FILE__, "ChannelParams.json")*"\n")
redirect_stdin(io)
using QGL
redirect_stdin(STDIN)

using Base.Test

# write your own tests here
@test 1 == 2
