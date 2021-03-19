using InvariantMeasures
using Test

@testset "InvariantMeasures.jl" begin

    include("TestDynamic.jl")
    include("TestHat.jl")
    include("TestAssemble.jl")
    include("TestAssembleHat.jl")
    include("TestEstimate.jl")
    include("TestNormOfPowers.jl")

end
