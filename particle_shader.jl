module ParticleShader  # extends Shader module

    FRAGMENT_SHADER_PATH = "res/shaders/particle_fragment.glsl"
    VERTEX_SHADER_PATH = "res/shaders/particle_vertex.glsl"

    using ...SpatialHashing, ..Shader, ModernGL, StructArrays, ...Camera

    
    struct BufferedTexture
        texture::Ref{GLuint}
        buffer::Ref{GLuint}
        texture_format::UInt32
        size::Int32
    end

    struct ParticleShaderData
        shader_data::Shader.ShaderData
        particle_texture::BufferedTexture
        particle_color_texture::BufferedTexture
        spatial_hash_texture::BufferedTexture
    end


    function create_buffered_texture(size::Int32, data_type::Type, texture_format::UInt32)
        data_buffer = Ref{GLuint}()
        glGenBuffers(1, data_buffer)
        glBindBuffer(GL_TEXTURE_BUFFER, data_buffer[])
        
        glBufferData(GL_TEXTURE_BUFFER,
                     size * sizeof(data_type),
                     data_type.(ones(size)), GL_DYNAMIC_DRAW)
        glBindBuffer(GL_TEXTURE_BUFFER, 0)
        
        texture = Ref{GLuint}()
        glGenTextures(1, texture)
        glBindTexture(GL_TEXTURE_BUFFER, texture[])
        glTexBuffer(GL_TEXTURE_BUFFER, texture_format, data_buffer[])
        glBindTexture(GL_TEXTURE_BUFFER, 0)
        
        return BufferedTexture(texture, data_buffer, texture_format, size)
    end

    function init( max_particles )
        shader_data = Shader.load(VERTEX_SHADER_PATH, FRAGMENT_SHADER_PATH)

        # Create a buffer for the particle data
        particle_buffer = create_buffered_texture(Int32(max_particles * 3), Float32, GL_RGB32F)
        spatial_hash_buffer = create_buffered_texture(Int32(max_particles * 2), UInt32, GL_RG32I)
        particle_color_buffer = create_buffered_texture(Int32(max_particles * 3), Float32, GL_RGB32F)

        return ParticleShaderData(shader_data, particle_buffer, particle_color_buffer, spatial_hash_buffer)
    end

    function buffer_from_cpu(buffered_texture::BufferedTexture, data::Array)
        glBindBuffer(GL_TEXTURE_BUFFER, buffered_texture.buffer[])
        glBufferSubData(GL_TEXTURE_BUFFER, 0, length(data) * sizeof(eltype(data)), data)
        glBindBuffer(GL_TEXTURE_BUFFER, 0)
    
        # Rebind texture to ensure OpenGL sees the updated data
        glBindTexture(GL_TEXTURE_BUFFER, buffered_texture.texture[])
        glTexBuffer(GL_TEXTURE_BUFFER, buffered_texture.texture_format, buffered_texture.buffer[])  
        glBindTexture(GL_TEXTURE_BUFFER, 0)
    end

    function array_from_buffer(buffered_texture::BufferedTexture, data_type::Type)
        glBindBuffer(GL_TEXTURE_BUFFER, buffered_texture.buffer[])
        data = Array{data_type}(undef, buffered_texture.size)
        glGetBufferSubData(GL_TEXTURE_BUFFER, 0, buffered_texture.size * sizeof(data_type), data)
        glBindBuffer(GL_TEXTURE_BUFFER, 0)
        return data
    end

    function update_particle_positions(particle_shader_data::ParticleShaderData, particles::SpatialHashing.HashData,)

        # for now move the data to the cpu and then back to the gpu
        cpu_particles = replace_storage(Array, particles.spatial_data)
        particle_x = cpu_particles.x
        particle_y = cpu_particles.y
        particle_z = cpu_particles.z

        particle_postions = hcat(particle_x, particle_y, particle_z)
        particle_postions = Float32.( vec(particle_postions') )

        buffer_from_cpu(particle_shader_data.particle_texture, particle_postions)

        cpu_particles = replace_storage(Array, particles.spatial_data)
        particle_red = cpu_particles.r
        particle_green = cpu_particles.g
        particle_blue = cpu_particles.b

        particle_colors = hcat(particle_red, particle_green, particle_blue)
        particle_colors = Float32.( vec(particle_colors') )

        buffer_from_cpu(particle_shader_data.particle_color_texture, particle_colors)

        # for now move the data to the cpu and then back to the gpu
        cpu_hash_values = replace_storage(Array, particles.hash)
        cpu_offset_values = replace_storage(Array, particles.offset)

        hash_table = hcat(cpu_hash_values, cpu_offset_values)
        hash_table = UInt32.( vec(hash_table') )
      
        buffer_from_cpu(particle_shader_data.spatial_hash_texture, hash_table)


        # gpu_particle_table = array_from_buffer(particle_shader_data.particle_texture, Float32)
        # gpu_hash_table = array_from_buffer(particle_shader_data.spatial_hash_texture, Int32)
        
        # println("GPU Particle positions")
        # display(hash_table)
        # display(gpu_hash_table)

#         grid_x = 1.0
#         grid_y = 1.0
#         grid_z = 0.0
#         # All particles
#         count = 0
#         
#         println("All Particle positions")
#         for i in 1:particles.n
#             if particle_x[i] > particles.grid_size * grid_x && particle_y[i] > particles.grid_size * grid_y && particle_x[i] < particles.grid_size * (grid_x + 1) && particle_y[i] < particles.grid_size * (grid_y + 1)
#                 println("Particle at: ", particle_x[i], particle_y[i], particle_z[i])
#                 count += 1
#             end
#         end
# 
#         println("Number of particles: ", count)
# 
#         # CPU check
#         println("CPU Particle positions")
#         start_hash = SpatialHashing.hash(grid_x,grid_y,grid_z,particles.n) 
#         start_index = cpu_offset_values[ start_hash ]
#         println("Start index: ", start_index)
#         current_hash = cpu_hash_values[ start_index ]
#         count = 0
#         while current_hash == start_hash
#             println("Particle at: ", particle_x[start_index], particle_y[start_index], particle_z[start_index])
#             start_index += 1
#             count += 1
#             current_hash = cpu_hash_values[ start_index ]
#         end
# 
#         println("Number of particles: ", count)
# 
#         # GPU check
#         println("GPU Particle positions")
#         start_hash = SpatialHashing.hash(grid_x,grid_y,grid_z,particles.n) 
#         start_index = gpu_hash_table[ (start_hash - 1) * 2 + 2 ]
#         current_hash = gpu_hash_table[ (start_index - 1) * 2 + 1]
#         println("Start index: ", start_index)
#         println("Start hash: ", start_hash, " Current hash: ", current_hash)
#         println("CPU_HASH: ", cpu_hash_values[ start_index ])
#         count = 0
#     
#         while current_hash == start_hash
#             println("Particle at: ", gpu_particle_table[ (start_index - 1) * 3 + 1], gpu_particle_table[ (start_index - 1) * 3 + 2], gpu_particle_table[ (start_index- 1) * 3 + 3])
#             start_index += 1
#             count += 1
#             current_hash = gpu_hash_table[ (start_index - 1) * 2 + 1]
#         end     
#         println("Number of particles: ", count)
# 
#         while true
# 
#         end

    end

    function use(particle_shader_data::ParticleShaderData, particles::SpatialHashing.HashData, camera::Camera.CameraData)

        shader_program = particle_shader_data.shader_data.shaderProgram
        particle_texture = particle_shader_data.particle_texture.texture
        spatial_hash_texture = particle_shader_data.spatial_hash_texture.texture
        particle_color_texture = particle_shader_data.particle_color_texture.texture
        numParticles = particles.n

        # Update particle positions
        update_particle_positions(particle_shader_data, particles)

        # Bind particle positions to texture buffer
        glActiveTexture(GL_TEXTURE0)
        glBindTexture(GL_TEXTURE_BUFFER, particle_texture[])

        # Bind spatial hash to texture buffer
        glActiveTexture(GL_TEXTURE1)
        glBindTexture(GL_TEXTURE_BUFFER, spatial_hash_texture[])

        glActiveTexture(GL_TEXTURE2)
        glBindTexture(GL_TEXTURE_BUFFER, particle_color_texture[])

        # Texture buffers
        loc = glGetUniformLocation(shader_program, "particlePositions")
        glUniform1i(loc, 0)
        loc = glGetUniformLocation(shader_program, "spatialHash")
        glUniform1i(loc, 1)
        loc = glGetUniformLocation(shader_program, "particleColors")
        glUniform1i(loc, 2)

        # Uniforms
        loc = glGetUniformLocation(shader_program, "numParticles")
        glUniform1i(loc, numParticles)
        loc = glGetUniformLocation(shader_program, "gridSize")
        glUniform1f(loc, particles.grid_size)
        loc = glGetUniformLocation(shader_program, "brightnessFactor")
        glUniform1f(loc, 0.1)

        # Domain 
        loc = glGetUniformLocation(shader_program, "boxMin")
        glUniform3f(loc, -1.0, -1.0, -1.0)
        loc = glGetUniformLocation(shader_program, "boxMax")
        glUniform3f(loc, 1.0, 1.0, 1.0)

        # Camera
        loc = glGetUniformLocation(shader_program, "cameraPosition")
        glUniform3f(loc, camera.position[1], camera.position[2], camera.position[3])
        loc = glGetUniformLocation(shader_program, "cameraDirection")
        glUniform3f(loc, camera.direction[1], camera.direction[2], camera.direction[3])
        loc = glGetUniformLocation(shader_program, "aspectRatio")
        glUniform1f(loc, camera.aspect_ratio)
        loc = glGetUniformLocation(shader_program, "fov")
        glUniform1f(loc, camera.fov)

        Shader.use(particle_shader_data.shader_data)
    end

end