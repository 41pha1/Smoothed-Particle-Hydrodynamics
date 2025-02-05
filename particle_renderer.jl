module ParticleRenderer
    include("shader.jl")
    include("particle_shader.jl")
    include("mesh.jl")

    using GLFW, ..SpatialHashing, .Shader, .Mesh, ..Window, .ParticleShader, ModernGL

    struct ParticleRendererData
        window::Window.WindowData
        screen_quad::Mesh.MeshData
        particle_shader::ParticleShader.ParticleShaderData
    end

    function init(width, height, title, max_particles)
        window = Window.init(width, height, title)

        particle_shader = ParticleShader.init( max_particles )
        screen_quad = Mesh.newQuadMesh( particle_shader.shader_data )

        return ParticleRendererData(window, screen_quad, particle_shader)
    end

    function redraw(renderer_data::ParticleRendererData, particles::SpatialHashing.HashData)
        glClear(GL_COLOR_BUFFER_BIT)

        ParticleShader.use(renderer_data.particle_shader, particles)
        Mesh.draw(renderer_data.screen_quad)

        GLFW.SwapBuffers(renderer_data.window.window)
        GLFW.PollEvents()

        return Window.update(renderer_data.window)
    end

end