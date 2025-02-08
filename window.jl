using GLFW, ModernGL
using StructArrays, CUDA


# # A self-contained example of CUDA/OpenGL interoperability.
# # A CUDA kernel writes pixel color values to a texture,
# # which is then displayed by OpenGL.
# # This is the first successful attempt I made at this, so
# # I have no idea about how effective a method it is.
# # Essentially, this OpenGL code creates a rectangle out of
# # two triangles, and maps a texture onto this rectangle.
# # The CUDA kernel then writes pixels to that texture.
# #
# # This should only require the Julia packages
# # - CUDA
# # - GLFW
# # - ModernGL
# #
# # All of this was pieced together from different sources:
# #
# # NVIDIA CUDA documentation
# # https://docs.nvidia.com/cuda/cuda-c-programming-guide/index.html#graphics-interoperability
# #
# # A Julia Discourse post by Tim Besard
# # https://discourse.julialang.org/t/cuarray-glmakie/52461/9
# #
# # A GitHub repository for the source code for the book CUDA For Engineers:
# # https://github.com/myurtoglu/cudaforengineers/tree/master/flashlight
# #
# # OpenGL 4 examples in Julia in GitHub
# # https://github.com/Gnimuc/Videre/tree/master/OpenGL%204%20Tutorials/09_texture_mapping
# #
# # GLFW.jl
# # https://github.com/JuliaGL/GLFW.jl
# 
# using GLFW
# using CUDA
# using ModernGL
# 
# # Render a checkered red surface.
# # Even thread blocks are red and odd blocks are black.
# function gpurender!(pixels, width)
# 	column = threadIdx().x - 1 + blockDim().x * (blockIdx().x - 1)
# 	row = threadIdx().y - 1 + blockDim().x * (blockIdx().y - 1)
# 
# 	# Colors are stored in RGBA format. We're setting them in UInt32
# 	# so R is the least significant byte, and A is the most significant,
# 	# so it looks like 0xAABBGGRR.
# 	red   = 0x000000FF
# 	black = 0x00000000
# 
# 	isoddblock = (blockIdx().x + blockIdx().y) % 2 == 0
# 	c = if isoddblock
# 		UInt32(black)
# 	else
# 		UInt32(red)
# 	end
# 
# 	# The pixel array is 1D, so figure out the index of this pixel
# 	pixelindex = column + row * width
# 	# and the array is of course 1-indexed, so add 1.
# 	pixels[pixelindex + 1] = c
# 
# 	return
# end
# 
# # The vertex and fragment shaders are OpenGL shaders that map the texture
# # to the triangles we display on the screen.
# # Adapted from
# # https://github.com/Gnimuc/Videre/tree/master/OpenGL%204%20Tutorials/09_texture_mapping
# const VERTEX_SHADER = """
# #version 410
# 
# layout (location = 0) in vec3 vertex_position;
# layout (location = 1) in vec2 vt; // per-vertex texture co-ords
# 
# out vec2 texture_coordinates;
# 
# void main() {
# 	texture_coordinates = vt;
# 	gl_Position = vec4(vertex_position, 1.0);
# }
# """
# 
# # From
# # https://github.com/Gnimuc/Videre/tree/master/OpenGL%204%20Tutorials/09_texture_mapping
# const FRAGMENT_SHADER = """
# #version 410
# 
# in vec2 texture_coordinates;
# uniform sampler2D basic_texture;
# out vec4 frag_colour;
# 
# void main() {
# 	vec4 texel = texture(basic_texture, texture_coordinates);
# 	frag_colour = texel;
# }
# """
# 
# # Here we map a Pixel Buffer Object (PBO) in OpenGL to a CUDA "graphics resource".
# # This graphics resource can be sent into the CUDA kernel above, as a UInt32 array
# # of pixel values.
# # The pixel values will then end up in the texture buffer, as far as I understand.
# # See the NVIDIA CUDA documentation for more info about what the methods
# # - cuGraphicsMapResources
# # - cuGraphicsUnmapResources
# # - cuGraphicsResourceGetMappedPointer_v2
# # actually do.
# # https://docs.nvidia.com/cuda/cuda-c-programming-guide/index.html#graphics-interoperability
# function render(resource)
# 	# Map CUDA graphics resource
# 	# This allows us to write to the Pixel Buffer Object from CUDA.
# 	CUDA.cuGraphicsMapResources(1, [resource], stream())
# 
# 	# Here we get a CUDA pointer to the graphics resource.
# 	deviceptrref = Ref{CUDA.CUdeviceptr}()
# 	numbytesref = Ref{Csize_t}()
# 	CUDA.cuGraphicsResourceGetMappedPointer_v2(deviceptrref, numbytesref, resource)
# 
# 	# Here we reinterpret it as a UInt32 CuArray.
# 	deviceptr = reinterpret(CuPtr{UInt32}, deviceptrref[])
# 	len = Int(numbytesref[] / sizeof(UInt32))
# 	# devbuffer is the final CuArray{UInt32} that we can send into our kernel,
# 	# and write the pixel values to.
# 	devbuffer = unsafe_wrap(CuArray, deviceptr, len)
# 
# 	# Width in pixels of the thing we're rendering.
# 	# It's needed to calculate the pixel index below.
# 	# Note that the width 1024 is hard coded in a couple of places.
# 	width = 1024
# 	@CUDA.sync @cuda threads=(16, 16) blocks=(64, 64) gpurender!(devbuffer, width)
# 
# 	# Unmap CUDA graphics resource
# 	CUDA.cuGraphicsUnmapResources(1, [resource], stream())
# end
# 
# # We want to create a PBO which is a "pixel buffer object".
# # That's where we will write our pixel color information.
# # Then we'll generate a texture.
# 
# function draw(window, vaoid::GLuint)
# 	width = 1024
# 	height = 1024
#     glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA,
#                  GL_UNSIGNED_BYTE, C_NULL)
# 
# 	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
# 	glViewport(0, 0, GLFW.GetFramebufferSize(window)...)
# 
# 	glBindVertexArray(vaoid)
# 	glDrawArrays(GL_TRIANGLES, 0, 6)
# end
# 
# # Create an OpenGL shader from the VERTEX_SHADER and FRAGMENT_SHADER above.
# # Adapted from
# # https://github.com/Gnimuc/Videre/tree/master/OpenGL%204%20Tutorials/09_texture_mapping
# function createshader(source::String, type::GLenum)
# 	id = glCreateShader(type)
# 
# 	glShaderSource(id, 1, Ptr{GLchar}[pointer(source)], C_NULL)
# 	glCompileShader(id)
# 
# 	result = Ref{GLint}()
# 	glGetShaderiv(id, GL_COMPILE_STATUS, result)
# 	if result[] != GL_TRUE
# 		@error "Bad shader: $(type)"
# 	end
# 
# 	id
# end
# 
# # Create an OpenGL program from the vertex and fragment shader.
# # Adapted from
# # https://github.com/Gnimuc/Videre/tree/master/OpenGL%204%20Tutorials/09_texture_mapping
# function createprogram(vertexshader, fragmentshader)
# 	id = glCreateProgram()
# 	glAttachShader(id, vertexshader)
# 	glAttachShader(id, fragmentshader)
# 
# 	glLinkProgram(id)
# 	result = Ref{GLint}()
# 	glGetProgramiv(id, GL_LINK_STATUS, result)
# 
# 	if result[] != GL_TRUE
# 		error("Could not link shader program")
# 	end
# 
# 	id
# end
# 
# function main()
# 	# The first CUDA launch takes a relatively long time (seconds), so we do it once at
# 	# startup. If we don't do this, then it will take seconds after we've created
# 	# the window, in the first render call. Then the window will seem to be frozen,
# 	# and unresponsive. You may then get a popup asking if you want to Wait or Force Quit.
# 	print("Preparing CUDA kernel...")
# 	fakearray = CuArray{UInt32}(undef, 1)
# 	@CUDA.sync @cuda launch=false gpurender!(fakearray, 0)
# 	println(" ready")
# 
# 	# Create a window and its OpenGL context.
# 	# Note that the width and height is an exact multiple of the number of threads per block,
# 	# and block size in the CUDA kernel call.
# 	# threads=(16, 16) blocks=(64, 64)
# 	# To have a different width or height, one needs to add boundary checks in the CUDA kernel.
# 	# Also note that the width value is hard coded in a couple of places, so if you modify this,
# 	# then also send the width/height around in the methods that need them.
# 	width = 1024
# 	height = 1024
# 	window = GLFW.CreateWindow(width, height, "Julia CUDA/OpenGL interop")
# 
# 	# Make the window's context current
# 	GLFW.MakeContextCurrent(window)
# 
# 	# Make a Pixel Buffer Object (PBO)
# 	# This is the buffer that the CUDA kernel writes pixel values to.
# 	# Adapted from CUDA For Engineers
# 	# https://github.com/myurtoglu/cudaforengineers/tree/master/flashlight
# 	pbo = Ref(GLuint(0))
# 	glGenBuffers(1, pbo)
# 	glBindBuffer(GL_PIXEL_UNPACK_BUFFER, pbo[])
# 	glBufferData(GL_PIXEL_UNPACK_BUFFER, 4*width*height*sizeof(GLubyte), C_NULL, GL_STREAM_DRAW)
# 
# 	# Make a Texture Object
# 	# The pixel values ends up in this texture.
# 	# Adapted from CUDA For Engineers
# 	# https://github.com/myurtoglu/cudaforengineers/tree/master/flashlight
# 	tex = Ref{GLuint}()
# 	glGenTextures(1, tex)
# 	glActiveTexture(GL_TEXTURE0)
# 	glBindTexture(GL_TEXTURE_2D, tex[])
# 
# 	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
# 
# 	# CUDA.CUgraphicsResource represents a _pointer_ type to graphics resource.
# 	# Here the Pixel Buffer Object is registered as a CUDA graphics resource.
# 	# This allows us to map it later in the `render` method.
# 	graphicsResourceRef = Ref{CUDA.CUgraphicsResource}()
# 	registerFlags = CUDA.CU_GRAPHICS_MAP_RESOURCE_FLAGS_WRITE_DISCARD
# 	CUDA.cuGraphicsGLRegisterBuffer(graphicsResourceRef, pbo[], registerFlags)
# 	graphicsResource = graphicsResourceRef[]
# 
# 	# Creating the Vertex Buffer Object, Texture Coordinates, and Vertex Array, is
# 	# adapted from
# 	# https://github.com/Gnimuc/Videre/tree/master/OpenGL%204%20Tutorials/09_texture_mapping
# 	# Make a Vertex Buffer Object, that will define our rectangle.
# 	# This defines a rectangle, using two triangles. The triangle fills the entire
# 	# screen.
# 	rectanglecoords = GLfloat[-1.0, -1.0, 0,
# 	                           1.0, -1.0, 0,
# 	                           1.0,  1.0, 0,
# 
# 	                           1.0,  1.0, 0,
# 	                          -1.0,  1.0, 0,
# 	                          -1.0, -1.0, 0]
# 	vbo = Ref{GLuint}()
# 	glGenBuffers(1, vbo)
# 	glBindBuffer(GL_ARRAY_BUFFER, vbo[])
# 	glBufferData(GL_ARRAY_BUFFER, sizeof(rectanglecoords), rectanglecoords, GL_DYNAMIC_DRAW)
# 
# 	# Make a Texture Coordinate thing that defines how our texture maps to our rectangle.
# 	texcoords = GLfloat[0.0, 0.0,
# 	                    1.0, 0.0,
# 	                    1.0, 1.0,
# 
# 	                    1.0, 1.0,
# 	                    0.0, 1.0,
# 	                    0.0, 0.0]
# 	texcoordvbo = Ref{GLuint}()
# 	glGenBuffers(1, texcoordvbo)
# 	glBindBuffer(GL_ARRAY_BUFFER, texcoordvbo[])
# 	glBufferData(GL_ARRAY_BUFFER, sizeof(texcoords), texcoords, GL_DYNAMIC_DRAW)
# 
# 	# Create a Vertex Array Object that ties them together, or something.
# 	vao = Ref{GLuint}()
# 	glGenVertexArrays(1, vao)
# 	glBindVertexArray(vao[])
# 	glBindBuffer(GL_ARRAY_BUFFER, vbo[])
# 	glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 0, C_NULL)
# 	glBindBuffer(GL_ARRAY_BUFFER, texcoordvbo[])
# 	glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 0, C_NULL)
# 	glEnableVertexAttribArray(0)
# 	glEnableVertexAttribArray(1)
# 
# 	# This clears the screen with a very green background.
# 	# This is useful for debugging. If you see some green in your window,
# 	# then it comes from here, and isn't covered by what we write from the
# 	# CUDA kernel.
# 	glClearColor(0.0, 1.0, 0.0, 1.0)
# 
# 	# OpenGL shader compilation and linking.
# 	vert_shader = createshader(VERTEX_SHADER, GL_VERTEX_SHADER)
# 	frag_shader = createshader(FRAGMENT_SHADER, GL_FRAGMENT_SHADER)
# 	shader_prog = createprogram(vert_shader, frag_shader)
# 	glUseProgram(shader_prog)
# 
# 	# Loop until the user closes the window
# 	while !GLFW.WindowShouldClose(window)
# 
# 		# Render here
# 		render(graphicsResource) # <- Call the CUDA kernel to write pixels.
# 		draw(window, vao[])
# 
# 		# Swap front and back buffers
# 		GLFW.SwapBuffers(window)
# 
# 		# Poll for and process events
# 		GLFW.PollEvents()
# 	end
# 
# 	# Unregister CUDA resources
# 	CUDA.cuGraphicsUnregisterResource(graphicsResource)
# 	glDeleteBuffers(1, pbo)
# 	glDeleteTextures(1, tex)
# 
# 	GLFW.DestroyWindow(window)
# end
# 
# main()

module Window

    using ModernGL, GLFW

    struct WindowData
        window::GLFW.Window
    end

    function init( width, height, title)
        GLFW.Init()
        window = GLFW.CreateWindow(width, height, title)
        GLFW.MakeContextCurrent(window)
        glViewport(0, 0, width, height)
        glPolygonMode(GL_FRONT_AND_BACK, GL_TRIANGLES)

        GLFW.SetInputMode(window, GLFW.CURSOR, GLFW.CURSOR_DISABLED)

        return WindowData(window)
    end

    function close(display::WindowData)
        GLFW.DestroyWindow(display.window)
        GLFW.Terminate()
    end

    function should_close(window_data::WindowData)
        return GLFW.WindowShouldClose(window_data.window)
    end

    function update(display::WindowData)

        if GLFW.GetKey(display.window, GLFW.KEY_ESCAPE) == GLFW.PRESS
            return false
        end

        return true
    end
end