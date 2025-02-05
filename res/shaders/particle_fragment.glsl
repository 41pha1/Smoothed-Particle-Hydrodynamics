    #version 330 core
    in vec2 texCoord; // Assuming texCoord spans the screen in normalized coordinates [-1,1]
    out vec4 FragColor;

    // Bind the texture buffer to a samplerBuffer
    uniform samplerBuffer particlePositions;
    uniform samplerBuffer particleColors;
    uniform isamplerBuffer spatialHash; // R: 32-bit hash, G: 32-bit offset into particlePositions
    uniform int numParticles;           // Pass the number of particles from your program
    uniform float gridSize;             // The size of the grid cells
    uniform float brightnessFactor;     // A factor to adjust the overall brightness

// 
//      @inline function hash_func(x::Float32, y::Float32, z::Float32, grid_size::Float32, n::Int64)
// 
//         grid_x::Int32 = Int32(floor(x / grid_size)) 
//         grid_y::Int32 = Int32(floor(y / grid_size))
//         grid_z::Int32 = Int32(floor(z / grid_size))
// 
//         intermediate::Int32 = Int32(grid_x) * Int32(881) + Int32(grid_y) * Int32(739) + Int32(grid_z) * Int32(997) + Int32(9733)
// 
//         return UInt32(abs(intermediate) % Int32(n))
//     end

    int hash(ivec3 gridPos, int n) {
        return  int(abs( int(gridPos.x) * 881 + int(gridPos.y) * 739 + int(gridPos.z) * 997 + 9733 ) % n);
    }

    void main() {
        float brightness = 0.0;
        // Transform texCoord if necessary; here we assume particles are in the same NDC space
        vec2 fragPos = texCoord; 
        vec3 pos = vec3(floor(fragPos.x / gridSize), floor(fragPos.y / gridSize), 0.0);
        vec3 color = vec3(0.0);
        
        for (int ix = -1; ix <= 1; ix++) {
            for (int iy = -1; iy <= 1; iy++) {
                
                ivec3 gridPos = ivec3(int(pos.x), int(pos.y), int(pos.z)) + ivec3(ix, iy, 0);
                int gridHash = hash(gridPos, numParticles);
                int startIdx = int(texelFetch( spatialHash, gridHash - 1 ).g) - 1;
                startIdx = max(0, startIdx);
                int currentHash = gridHash; 
                int count = 0;

                while ((currentHash == gridHash || count < 5) && startIdx < numParticles ) {
                    vec3 particle = texelFetch(particlePositions, startIdx).xyz;
                    ivec3 particle_grid = ivec3(int(floor(particle.x / gridSize)), int(floor(particle.y / gridSize)), 0);

                    // if (particle_grid != gridPos) {
                    //     continue;
                    // }

                    float dist = distance(fragPos, particle.xy);
                    color += exp(-dist * 150.0) * texelFetch(particleColors, startIdx).rgb;

                    startIdx++;
                    count++;
                    currentHash = hash(particle_grid, numParticles);
                }
            }
        }

        color *= brightnessFactor;
        FragColor = vec4(color, 1.0);
//      FragColor = vec4(vec3(gridHash - predictedHash) / 1.0, 1.0);
    }