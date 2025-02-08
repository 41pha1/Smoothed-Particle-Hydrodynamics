module ParticleSimulation

    using CUDA, StaticArrays, StructArrays, AcceleratedKernels, ..SpatialHashing, ..Input
    import StructArrays: StructArray

    mutable struct Particle
        x::Float32
        y::Float32
        z::Float32

        vx::Float32
        vy::Float32
        vz::Float32

        r::Float32
        g::Float32
        b::Float32

        mass::Float32
        density::Float32
        pressure::Float32
    end

    struct SimulationData
        particle_hash::SpatialHashing.HashData

        weight_func::Function
        d_weight_func::Function
        d2_weight_func::Function

        sigma::Float32

        rho0::Float32
        mu::Float32
        k::Float32

        gravity::SVector{3, Float32}
    end

    function EXPONENTIAL_WEIGHTS(sigma)
        return (
            func = (r) -> exp(-r * r / (sigma * sigma)),
            dfunc = (r) -> exp(-r * r / (sigma * sigma)) * (-2.0 * r / (sigma * sigma)),
            d2func = (r) -> exp(-r * r / (sigma * sigma)) * (4.0 * r * r / (sigma * sigma * sigma * sigma) - 2.0 / (sigma * sigma))
        )
    end

    function init(n, grid_size::Float32)

        nx = ceil(sqrt(n))
        cpu_particles = StructArray([Particle(((i % nx) / nx) , ((i / nx) / nx), rand(Float32),
                                              zero(Float32), zero(Float32), zero(Float32),
                                              zero(Float32), zero(Float32), zero(Float32),
                                              one(Float32), zero(Float32), zero(Float32)) for i in 1:n])

                                            
        for i in 1:n
            random = rand(Float32)
            if random > 0.98
                cpu_particles.g[i] = 1.0 + (rand(Float32) - 0.5) * 0.1
                cpu_particles.r[i] = 1.0 + (rand(Float32) - 0.5) * 0.1
                cpu_particles.b[i] = 1.0 + (rand(Float32) - 0.5) * 0.1
                cpu_particles.mass[i] = 2.0
            else
                cpu_particles.b[i] = 1.0 - (rand(Float32) - 0.5) * 0.1
                cpu_particles.g[i] = rand(Float32) * 0.75
            end
        end

        display(cpu_particles)


        spatial_hash = SpatialHashing.init(replace_storage(CuArray, StructArray(cpu_particles)), grid_size)

        sigma = grid_size / 2.0
        
        return SimulationData(spatial_hash, 
                                EXPONENTIAL_WEIGHTS(sigma).func,
                                EXPONENTIAL_WEIGHTS(sigma).dfunc,
                                EXPONENTIAL_WEIGHTS(sigma).d2func,
                                sigma,
                                 10.0, 2.0, 100.0,
                                [0.0, -981, 0.0]
                            )
    end

    function CUBIC_WEIGHTS(sigma)
        return (
            func = (r) -> begin
                if r < sigma
                    val = 1.0 - abs(r) / sigma
                    return val * val * val
                else
                    return 0.0
                end
            end,
            dfunc = (r) -> begin
                if r < sigma
                    val = 1.0 - abs(r) / sigma
                    return -3.0 * val * val * sign(r) / sigma
                else
                    return 0.0
                end
            end,
            d2func = (r) -> begin
                if r < sigma
                    val = 1.0 - abs(r) / sigma
                    return 6.0 * val / (sigma * sigma)
                else
                    return 0.0
                end
            end
        )
    end

    function density_pressure_kernel( particles, hash, offset, sigma::Float32, grid_size::Float32, n::Int64, rho0::Float32, k::Float32 )
        i = (blockIdx().x - 1) * blockDim().x + threadIdx().x
    
        if i > n
            return
        end
    
        density_value = zero(Float32)
    
        pos_x, pos_y, pos_z = particles.x[i], particles.y[i], particles.z[i]
    
        for ix = -1:1, iy = -1:1, iz = -1:1
            hash_index = SpatialHashing.hash_func(pos_x + ix * grid_size, pos_y + iy * grid_size, pos_z + iz * grid_size, grid_size, n)
            
            if hash_index > 0 && hash_index <= length(offset)
                startIdx = offset[hash_index]
                currentHash = hash_index
    
                while startIdx > 0 && startIdx <= n && currentHash == hash_index
                    other_x, other_y, other_z = particles.x[startIdx], particles.y[startIdx], particles.z[startIdx]
                    toOther_x = other_x - pos_x
                    toOther_y = other_y - pos_y
                    toOther_z = other_z - pos_z
                    distance = CUDA.sqrt(toOther_x^2 + toOther_y^2 + toOther_z^2)

                    if distance < grid_size
                        density_value += particles.mass[startIdx] * CUDA.exp(-distance * distance / (sigma * sigma))
                    end

                    currentHash = hash[startIdx]
                    startIdx += 1
                end
            end
        end
    
        particles.density[i] = max(density_value, particles.mass[i])
        particles.pressure[i] = k * ((density_value / rho0)^7 - 1.0)
    
        return
    end

    function particle_update_kernel(particles, hash, offset, 
        sigma::Float32, grid_size::Float32, n::Int64, mu::Float32, 
        gravity_x::Float32, gravity_y::Float32, gravity_z::Float32, 
        mouse_x::Float32, mouse_y::Float32, mouse_dx::Float32, mouse_dy::Float32, mouse_left::Int32, mouse_right::Int32,
        dt::Float32)
        i = (blockIdx().x - 1) * blockDim().x + threadIdx().x

        accX = 0.0
        accY = 0.0
        accZ = 0.0

        density = particles.density[i]
        pressure = particles.pressure[i]
        mass = particles.mass[i]

        pos_x, pos_y, pos_z = particles.x[i], particles.y[i], particles.z[i]
        vel_x, vel_y, vel_z = particles.vx[i], particles.vy[i], particles.vz[i]
    
        for ix = -1:1, iy = -1:1, iz = -1:1
            hash_index = SpatialHashing.hash_func(pos_x + ix * grid_size, pos_y + iy * grid_size, pos_z + iz * grid_size, grid_size, n)
            
            if hash_index > 0 && hash_index <= length(offset)
                startIdx = offset[hash_index]
                currentHash = hash_index
    
                while startIdx > 0 && startIdx <= n && currentHash == hash_index
                    other_x, other_y, other_z = particles.x[startIdx], particles.y[startIdx], particles.z[startIdx]
                    toOther_x = other_x - pos_x
                    toOther_y = other_y - pos_y
                    toOther_z = other_z - pos_z
                    distance = max(CUDA.sqrt(toOther_x^2 + toOther_y^2 + toOther_z^2), 0.0001)

                    if distance < grid_size
                        
                        if i == startIdx
                            startIdx += 1
                            continue
                        end
                        
                        # Pressure acc 
                        pressure_average = 0.5 * ( pressure * mass / density + particles.pressure[startIdx] * particles.mass[startIdx] / particles.density[startIdx] )

                        weight = CUDA.exp(-distance * distance / (sigma * sigma) ) * (-2.0 * distance / (sigma * sigma))

                        accX += (toOther_x / distance) / density * weight * pressure_average 
                        accY += (toOther_y / distance) / density * weight * pressure_average
                        accZ += (toOther_z / distance) / density * weight * pressure_average

                        # Viscosity acc
                        vel_X_average = 0.5 * (vel_x * mass / density - particles.vx[startIdx] * particles.mass[startIdx] / particles.density[startIdx])
                        vel_Y_average = 0.5 * (vel_y * mass / density - particles.vy[startIdx] * particles.mass[startIdx] / particles.density[startIdx])
                        vel_Z_average = 0.5 * (vel_z * mass / density - particles.vz[startIdx] * particles.mass[startIdx] / particles.density[startIdx])

                        weight = CUDA.exp(-distance * distance / (sigma * sigma)) * (4.0 * distance * distance / (sigma * sigma * sigma * sigma) - 2.0 / (sigma * sigma))
                        
                        accX -= mu * weight * vel_X_average / density
                        accY -= mu * weight * vel_Y_average / density
                        accZ -= mu * weight * vel_Z_average / density
                    end

                    currentHash = hash[startIdx]
                    startIdx += 1
                end
            end
        end

        accX += gravity_x
        accY += gravity_y
        accZ += gravity_z

        # mouseDist = max(CUDA.sqrt((pos_x - mouse_x)^2 + (pos_y - mouse_y)^2 + (pos_z - 0.0)^2), 0.0001)

#         if mouseDist < 0.15
#             strength = 10000.0
#             
#             if mouse_right != 1 && mouse_left != 1
#                 strength = 0.0
#             end
# 
#             if mouse_right == 1
#                 strength = -strength
#             end
# 
#             accX += (pos_x - mouse_x) / mouseDist * strength
#             accY += (pos_y - mouse_y) / mouseDist * strength
#         end

        particles.vx[i] += dt * accX
        particles.vy[i] += dt * accY
        particles.vz[i] += dt * accZ

        # particles.vx[i] *= 0.99
        # particles.vy[i] *= 0.99
        
        elasticity = 0.99
        # particles.vz[i] += dt * accZ

     

        particles.vx[i] = clamp(particles.vx[i], -50.0, 50.0)
        particles.vy[i] = clamp(particles.vy[i], -50.0, 50.0)
        particles.vz[i] = clamp(particles.vz[i], -50.0, 50.0)

        if particles.x[i] < -1.0
            particles.x[i] = -2.0 - particles.x[i]
            particles.vx[i] = elasticity * abs(particles.vx[i])
        end

        if particles.x[i] > 1.0
            particles.x[i] = 2.0 - particles.x[i]
            particles.vx[i] = -elasticity * abs(particles.vx[i]) 
        end

        if particles.y[i] < -1.0
            particles.y[i] = -2.0 - particles.y[i]
            particles.vy[i] = elasticity * abs(particles.vy[i]) 
        end

        if particles.y[i] > 1.0
            particles.y[i] = 2.0 - particles.y[i]
            particles.vy[i] = -elasticity * abs(particles.vy[i]) 
        end

        if particles.z[i] < -1.0
            particles.z[i] = -2.0 - particles.z[i]
            particles.vz[i] = elasticity * abs(particles.vz[i]) 
        end

        if particles.z[i] > 1.0
            particles.z[i] = 2.0 - particles.z[i]
            particles.vz[i] = -elasticity * abs(particles.vz[i])
        end

        particles.x[i] = clamp(particles.x[i], -1.0, 1.0)
        particles.y[i] = clamp(particles.y[i], -1.0, 1.0)
        particles.z[i] = clamp(particles.z[i], -1.0, 1.0)

        if i <= length(particles.x)
            particles.x[i] += particles.vx[i] * dt
            particles.y[i] += particles.vy[i] * dt
            particles.z[i] += particles.vz[i] * dt
        end

        return
    end

    function update(simulation_data::SimulationData, input::Input.InputData, dt::Float64)


        @cuda threads=256 blocks=cld(simulation_data.particle_hash.n, 256) density_pressure_kernel(
                simulation_data.particle_hash.spatial_data, 
                simulation_data.particle_hash.hash, 
                simulation_data.particle_hash.offset, 
                simulation_data.sigma,
                simulation_data.particle_hash.grid_size,
                simulation_data.particle_hash.n, 
                simulation_data.rho0,
                simulation_data.k
            )

        # CUDA.@allowscalar display(simulation_data.particle_hash.spatial_data)
        res = 1200.0
        screenMouseX = (input.MouseX / res) * 2.0 - 1.0
        screenMouseY = 1.0 - (input.MouseY / res) * 2.0

        @cuda threads=256 blocks=cld(simulation_data.particle_hash.n, 256) particle_update_kernel(
                simulation_data.particle_hash.spatial_data, 
                simulation_data.particle_hash.hash, 
                simulation_data.particle_hash.offset, 
                simulation_data.sigma,
                simulation_data.particle_hash.grid_size,
                simulation_data.particle_hash.n, 
                simulation_data.mu,
                simulation_data.gravity[1],
                simulation_data.gravity[2],
                simulation_data.gravity[3],
                Float32(screenMouseX), Float32(screenMouseY), 
                Float32(input.MouseDX / res), Float32(input.MouseDY / res), 
                Int32(input.MouseLeft), Int32(input.MouseRight),
                Float32.(dt)
            )

        SpatialHashing.update(simulation_data.particle_hash)
    end
end