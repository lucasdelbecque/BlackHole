cmake_minimum_required(VERSION 3.20)
project(BlackHole CXX OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_OBJCXX_STANDARD 17)

# Chemin direct vers le compilateur Metal (bypass xcrun)
set(METAL_COMPILER /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/metal)

add_custom_command(
        OUTPUT ${CMAKE_BINARY_DIR}/blackhole.metallib
        COMMAND ${METAL_COMPILER}
        ${CMAKE_SOURCE_DIR}/shaders/blackhole.metal
        -o ${CMAKE_BINARY_DIR}/blackhole.metallib
        DEPENDS ${CMAKE_SOURCE_DIR}/shaders/blackhole.metal
)
add_custom_target(MetalShader DEPENDS ${CMAKE_BINARY_DIR}/blackhole.metallib)

add_executable(BlackHole
        src/main.mm
        src/renderer.mm
        src/geodesics.cpp
        shaders/blackhole.metal
)

add_dependencies(BlackHole MetalShader)

target_include_directories(BlackHole PRIVATE src)

# Frameworks macOS
target_link_libraries(BlackHole
        "-framework Metal"
        "-framework MetalKit"
        "-framework Cocoa"
        "-framework QuartzCore"
)

# Copier le .metallib à côté de l'exécutable
add_custom_command(TARGET BlackHole POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy
        ${CMAKE_BINARY_DIR}/blackhole.metallib
        $<TARGET_FILE_DIR:BlackHole>/blackhole.metallib
)