module Shader

    using GLFW, ModernGL

    struct ShaderData
        shaderProgram::UInt32
    end

    function compile_shader(source, shader_type)
        shader = glCreateShader(shader_type)
        glShaderSource(shader, 1, Ptr{GLchar}[pointer(source)], C_NULL)
        glCompileShader(shader)

        success = Ref{GLint}(0)
        glGetShaderiv(shader, GL_COMPILE_STATUS, success)
        if success[] == 0
            log_length = Ref{GLint}(0)
            glGetShaderiv(shader, GL_INFO_LOG_LENGTH, log_length)
            if log_length[] > 0
                error_log = Vector{GLchar}(undef, log_length[])
                glGetShaderInfoLog(shader, log_length[], C_NULL, pointer(error_log))
                println("Shader compilation error: ", String(error_log))
            end
        end

        return shader
    end

    function load(vertex_shader_path, fragment_shader_path)
        vertex_shader_source = read(vertex_shader_path, String)
        fragment_shader_source = read(fragment_shader_path, String)

        vertex_shader = compile_shader(vertex_shader_source, GL_VERTEX_SHADER)
        fragment_shader = compile_shader(fragment_shader_source, GL_FRAGMENT_SHADER)

        shader_program = glCreateProgram()
        glAttachShader(shader_program, vertex_shader)
        glAttachShader(shader_program, fragment_shader)
        glLinkProgram(shader_program)

        return ShaderData(shader_program)
    end

    function use(shader_data::ShaderData)
        glUseProgram(shader_data.shaderProgram)
    end
    
    function delete(shader_data::ShaderData)
        glDeleteProgram(shader_data.shaderProgram)
    end
end