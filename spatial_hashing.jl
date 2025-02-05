module SpatialHashing

    using CUDA, StructArrays, AcceleratedKernels

    struct HashData 
        spatial_data::StructArray{T} where T # Must have x, y, z, hash fields

        hash::CuArray{UInt32}
        offset::CuArray{UInt32}

        gpu_identity::CuArray{Int32}
        gpu_perm::CuArray{Int32}

        n::Int64
        grid_size::Float32
    end

    @inline function hash_func(x::Float32, y::Float32, z::Float32, grid_size::Float32, n::Int64)

        grid_x::Int32 = Int32(floor(x / grid_size)) 
        grid_y::Int32 = Int32(floor(y / grid_size))
        grid_z::Int32 = Int32(floor(z / grid_size))

        intermediate::Int32 = Int32(grid_x) * Int32(881) + Int32(grid_y) * Int32(739) + Int32(grid_z) * Int32(997) + Int32(9733)

        return UInt32(abs(intermediate) % Int32(n))
    end

    function hash_data_kernel(hash, particles, grid_size::Float32, n::Int64)
        i = (blockIdx().x - 1) * blockDim().x + threadIdx().x

        if i <= n
            hash[i] = hash_func(particles.x[i], particles.y[i], particles.z[i], grid_size, n)
        end

        return
    end

    function compute_data_hash!(spatial_hash::HashData)
        threads = 256
        n = spatial_hash.n
        blocks = cld(n, threads)

        @cuda threads=threads blocks=blocks hash_data_kernel(spatial_hash.hash, spatial_hash.spatial_data, spatial_hash.grid_size, n)
        CUDA.synchronize()
    end

    function sort_and_search!(spatial_hash::HashData)
        AcceleratedKernels.sortperm!(spatial_hash.gpu_perm, spatial_hash.hash)
        AcceleratedKernels.permute!(spatial_hash.hash, spatial_hash.gpu_perm)
        AcceleratedKernels.permute!(spatial_hash.spatial_data, spatial_hash.gpu_perm)
        AcceleratedKernels.searchsortedfirst!(spatial_hash.offset, spatial_hash.hash, spatial_hash.gpu_identity)
    end

    function init(spatial_data, grid_size::Float32)
        n = length(spatial_data)
        return HashData(
            spatial_data, 
            CUDA.zeros(UInt32, n), 
            CUDA.zeros(UInt32, n), 
            cu(collect(1:n)), 
            CUDA.zeros(Int32, n),
            n,
            grid_size
        )
    end

    function update(spatial_hash::HashData)
        compute_data_hash!(spatial_hash)
        sort_and_search!(spatial_hash)
    end

end