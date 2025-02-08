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

    uniform vec3 cameraPosition;
    uniform vec3 cameraDirection;
    uniform vec3 boxMin, boxMax;
    uniform float aspectRatio;
    uniform float fov;


    int hash(ivec3 gridPos, int n) {
        return abs( ((int(gridPos.x) * 73856093) ^ (int(gridPos.y) * 19349663) ^ (int(gridPos.z) * 83492791)) + 10) % n;
    }

    bool intersectRayBox(vec3 rayOrigin, vec3 rayDirection) {
        vec3 invDir = 1.0 / rayDirection;
        
        vec3 tMin = (boxMin - rayOrigin) * invDir;
        vec3 tMax = (boxMax - rayOrigin) * invDir;

        vec3 t1 = min(tMin, tMax);
        vec3 t2 = max(tMin, tMax);

        float tNear = max(t1.x, max(t1.y, t1.z));
        float tFar = min(t2.x, min(t2.y, t2.z));

        if (tNear > tFar || tFar < 0.0) {
            return false; // No intersection
        }

        return true;
    }

    float smin( float a, float b, float k )
    {
        float r = exp2(-a/k) + exp2(-b/k);
        return -k*log2(r);
    }

    vec4 particleMap(vec3 pos, vec3 dir)
    {
        if (!intersectRayBox(pos, dir))
            return vec4(vec3(0.0), 1e5);

        float particleRadius = 0.001;
        float closestDist = gridSize;
        ivec3 gridPos = ivec3(floor(pos.x / gridSize), floor(pos.y / gridSize), floor(pos.z / gridSize));

        vec3 color = vec3(0.0);
        float totalWeight = 0.0;

        for (int ix = -1; ix <= 1; ix++) {
            for (int iy = -1; iy <= 1; iy++) {
                for (int iz = -1; iz <= 1; iz++) {
                    ivec3 offsetGrid = ivec3(ix, iy, iz);

                    int gridHash = hash(gridPos + offsetGrid, numParticles);
                    int startIdx = max(0, int(texelFetch( spatialHash, gridHash - 1 ).g) - 1);
                    int currentHash = gridHash; 

                    while (currentHash == gridHash && startIdx < numParticles ) {
                        vec3 particle = texelFetch(particlePositions, startIdx).xyz;
                        ivec3 particle_grid = ivec3(int(floor(particle.x / gridSize)), int(floor(particle.y / gridSize)), int(floor(particle.z / gridSize)));

                        // if (particle_grid == gridPos) {
                        float dist = distance(pos, particle);
                        closestDist = smin(closestDist, dist - particleRadius, gridSize * 0.15);

                        
                        vec3 particleColor = texelFetch(particleColors, startIdx).rgb;
                        float weight = 1.0 / (1.0 + (dist * dist) * 1000.0);
                        color += particleColor * weight;
                        totalWeight += weight;
                        // }

                        startIdx++;
                        currentHash = hash(particle_grid, numParticles);
                    }
                }
            }
        }

        return vec4(color / totalWeight, closestDist);
    }

    vec4 floorMap(vec3 pos) 
    {
        float distance =  abs(pos.y + 1.0);

        float gridSize = 0.1;

        float gridX = floor(pos.x / gridSize);
        float gridZ = floor(pos.z / gridSize);

        vec3 color = vec3(0.1);

        if (mod(gridX + gridZ, 2.0) < 1.0) {
            color = vec3(0.2);
        }

        return vec4(color, distance);
    }

    vec3 skyMap(vec3 dir) {
        float t = 0.5 * (dir.y + 1.0);
        return mix(vec3(1.0), vec3(0.5, 0.7, 1.0), t);
    }

    vec4 combineMaps(vec4 a, vec4 b) {
        return a.a < b.a ? a : b;
    }

    vec4 map(vec3 pos, vec3 dir) {
        return combineMaps(particleMap(pos, dir), floorMap(pos));
    }

    float diffuse(vec3 n,vec3 l,float p) {
        return pow(dot(n,l) * 0.4 + 0.6,p);
    }
    
    float specular(vec3 n,vec3 l,vec3 e,float s) {    
        float nrm = (s + 8.0) / (3.141 * 8.0);
        return pow(max(dot(reflect(e,n),l),0.0),s) * nrm;
    }

    const float EPSILON = 0.0001;

    vec3 calcNormal(vec3 pos, vec3 dir) {
        vec2 e = vec2(EPSILON, 0.0);
        return normalize(vec3(map(pos+e.xyy, dir).a - map(pos-e.xyy, dir).a, map(pos+e.yxy, dir).a - map(pos-e.yxy, dir).a, map(pos+e.yyx, dir).a - map(pos-e.yyx, dir).a));
    }

    vec4 march(vec3 ro, vec3 rd)
    {
        float disO = 0.;
        
        for(int i = 0; i < 1000; i++)
        {
            vec3 pos = ro+rd*disO;
            vec4 dd = map(pos, rd);
            disO += dd.a;
            
            if(dd.a < EPSILON)
                return vec4(dd.rgb, disO);
            if(disO > 200.)
                break;
        }
        return vec4(-1.);
    }

    void main() {
        float brightness = 0.0;
        // Transform texCoord if necessary; here we assume particles are in the same NDC space
        vec2 fragPos = texCoord; // * 2.0 - 1.0;

        // Calculate Camera Ray
        float zoom = 1.0 / tan(fov / 2.0);
        vec3 up = vec3(0.0, 1.0, 0.0);
        vec3 front = normalize(cameraDirection);
        vec3 right = normalize(cross(front, up));
        up = normalize(cross(right, front));

        vec3 ro = cameraPosition;
        vec3 rd = normalize(front + right * aspectRatio * fragPos.x * zoom + up * fragPos.y * zoom);

        vec3 col = skyMap(rd);

        vec4 result = march(ro, rd);
        float d = result.a;

        if(d > 0.)
        {    
            vec3 diffCol = result.rgb;

            vec3 pos = ro+rd*d;
            vec3 nor = calcNormal(pos, rd);
            vec3 lDir = normalize(vec3(0.5, 0.5, -1.));
            vec3 base = vec3(0.9);
            float dif = diffuse(nor, lDir, 1.);
            // float ao1 = calcAO(pos, nor, 64., 1.5);
            // float ao2 = calcAO(pos, nor, 32.,EPSILON * 50.);
            vec3 ref = normalize(lDir - (2.*dot(nor, lDir)*nor));
            float spec = clamp(dot(normalize(pos-ro), ref), 0., 1.);
            spec = pow(spec, 30.);

            col = vec3(diffCol*mix(dif, 1., 0.2)*0.8);
            col += spec*0.1;
            col *= 2.6*exp(d*-0.07);
        }

        col = pow( col, vec3(1.0,1.0,1.4) ) + vec3(0.0,0.02,0.12);
        vec2 q = texCoord * 0.5 + 0.5;
        col *= pow( 16.0*q.x*q.y*(1.0-q.x)*(1.0-q.y), 0.2 );
        FragColor =vec4(pow(col,vec3(0.75)), 1.0);
    }