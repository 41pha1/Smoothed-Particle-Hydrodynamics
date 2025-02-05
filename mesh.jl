module Mesh

    using ..Shader, GLFW, ModernGL

    struct MeshData
        vao::UInt32
        vbo::UInt32
        ebo::UInt32

        n_indices::Int32
        n_vertices::Int32

        draw_mode::Int32

        shader_data::Shader.ShaderData
    end

    function newQuadMesh( shader::Shader.ShaderData )
        vertices = Float32[
            -1.0, -1.0, 0.0,
            1.0, -1.0, 0.0,
            -1.0, 1.0, 0.0,
            1.0, 1.0, 0.0
        ]

        vertices = reshape(vertices', length(vertices))

        vao = Ref{GLuint}()
        vbo = Ref{GLuint}()
        glGenVertexArrays(1, vao)
        glGenBuffers(1, vbo)

        glBindVertexArray(vao[])

        glBindBuffer(GL_ARRAY_BUFFER, vbo[])
        glBufferData(GL_ARRAY_BUFFER, length(vertices) * sizeof(Float32), vertices, GL_STATIC_DRAW)

        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 3 * sizeof(Float32), C_NULL)
        glEnableVertexAttribArray(0)

        glBindBuffer(GL_ARRAY_BUFFER, 0)
        glBindVertexArray(0)

        return MeshData(vao[], vbo[], 0, 0, 4, GL_TRIANGLE_STRIP, shader)
    end

    function draw(mesh_data::MeshData)
        glBindVertexArray(mesh_data.vao)
        glDrawArrays(mesh_data.draw_mode, 0, mesh_data.n_vertices)
        glBindVertexArray(0)
    end

end