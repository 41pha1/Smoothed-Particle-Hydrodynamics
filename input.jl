module Input

    using GLFW

    mutable struct InputData
        MouseX::Float32
        MouseY::Float32
        MouseDX::Float32
        MouseDY::Float32

        MouseLeft::Bool
        MouseRight::Bool

        KeyW::Bool
        KeyA::Bool
        KeyS::Bool
        KeyD::Bool

        KeySpace::Bool
        KeyShift::Bool

    end


    function init()
        return InputData(0.0, 0.0, 0.0, 0.0, false, false, false, false, false, false, false, false)
    end

    function update(input::InputData, window::GLFW.Window)
        input.MouseDX, input.MouseDY = GLFW.GetCursorPos(window)
        input.MouseDX -= input.MouseX
        input.MouseDY -= input.MouseY
        input.MouseX, input.MouseY = GLFW.GetCursorPos(window)

        input.MouseLeft = GLFW.GetMouseButton(window, GLFW.MOUSE_BUTTON_LEFT) == GLFW.PRESS
        input.MouseRight = GLFW.GetMouseButton(window, GLFW.MOUSE_BUTTON_RIGHT) == GLFW.PRESS

        input.KeyW = GLFW.GetKey(window, GLFW.KEY_W) == GLFW.PRESS
        input.KeyA = GLFW.GetKey(window, GLFW.KEY_A) == GLFW.PRESS
        input.KeyS = GLFW.GetKey(window, GLFW.KEY_S) == GLFW.PRESS
        input.KeyD = GLFW.GetKey(window, GLFW.KEY_D) == GLFW.PRESS

        input.KeySpace = GLFW.GetKey(window, GLFW.KEY_SPACE) == GLFW.PRESS
        input.KeyShift = GLFW.GetKey(window, GLFW.KEY_LEFT_SHIFT) == GLFW.PRESS        

    end

end