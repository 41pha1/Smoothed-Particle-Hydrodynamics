module Camera
    using ..Input

    mutable struct CameraData
        position::Vector{Float32}
        direction::Vector{Float32}
        aspect_ratio::Float32
        fov::Float32

        pitch::Float32
        yaw::Float32
    end

    function init(aspect_ratio::Float32, fov::Float32)
        position = [0.0, 0.0, -1.0]
        direction = [0.0, 0.0, 1.0]
        return CameraData(position, direction, aspect_ratio, fov, 0.0, 0.0)
    end

    function update(input::Input.InputData, camera::CameraData, dt::Float64)
        speed = 4.0
        rotation_speed = 0.01

        if input.KeyW
            camera.position[1] += speed * cos(camera.yaw) * dt
            camera.position[3] += speed * sin(camera.yaw) * dt
        end
        if input.KeyS
            camera.position[1] -= speed * cos(camera.yaw) * dt
            camera.position[3] -= speed * sin(camera.yaw) * dt
        end
        if input.KeyA
            camera.position[1] += speed * sin(camera.yaw) * dt
            camera.position[3] -= speed * cos(camera.yaw) * dt
        end
        if input.KeyD
            camera.position[1] -= speed * sin(camera.yaw) * dt
            camera.position[3] += speed * cos(camera.yaw) * dt
        end
        if input.KeySpace
            camera.position[2] += speed * dt
        end
        if input.KeyShift
            camera.position[2] -= speed * dt
        end

        camera.yaw += input.MouseDX * rotation_speed
        camera.pitch -= input.MouseDY * rotation_speed
        camera.pitch = clamp(camera.pitch, -Float32(pi / 2), Float32(pi / 2))

        camera.direction[1] = cos(camera.yaw) * cos(camera.pitch)
        camera.direction[2] = sin(camera.pitch)
        camera.direction[3] = sin(camera.yaw) * cos(camera.pitch)

        camera.direction ./= (camera.direction[1]^2 + camera.direction[2]^2 + camera.direction[3]^2)^0.5
    end

end