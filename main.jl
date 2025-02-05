using CUDA
using GLMakie
using StructArrays
using AcceleratedKernels
using BenchmarkTools

include("spatial_hashing.jl")
include("window.jl")

include("input.jl")
include("particle_simulation.jl")
include("particle_renderer.jl")

import .ParticleSimulation
import .SpatialHashing
import .ParticleRenderer
import .Window
import .Input

# Initialisation
n = 2 << 14
simulation = ParticleSimulation.init(n, Float32(0.02))
renderer = ParticleRenderer.init(1200, 1200, "SPH", n)
input = Input.init()
SpatialHashing.update(simulation.particle_hash)

# Main loop
target_fps = 240
frame_time = 1.0 / target_fps

last_time = time()
dt = 0.0

while !Window.should_close(renderer.window)
    
    Input.update(input, renderer.window.window)
    ParticleSimulation.update(simulation, input, frame_time * 0.05)
    
    if !ParticleRenderer.redraw(renderer, simulation.particle_hash)
        break
    end

    sleep_time = frame_time - (time() - last_time)
    if sleep_time > 0
        sleep(sleep_time)
    end

    global dt = time() - last_time
    global last_time = time()
end

Window.close(renderer.window)
