# ============================================================================
#  NLOSFeatureEmbeddings  -  CUDA / OpenGL transient renderer
#  Windows 11 + Visual Studio + CUDA 11.8 build file
#
#  Configure (from cuda-render/):
#     cmake -B build -S . -G "Visual Studio 17 2022" -A x64 -T v142 ^
#           -DCMAKE_TOOLCHAIN_FILE=C:/dev/vcpkg/scripts/buildsystems/vcpkg.cmake
#  Build:
#     cmake --build build --config Release
# ============================================================================
cmake_minimum_required(VERSION 3.20)
project(nlos_render LANGUAGES CXX CUDA)

# ---- language standards -----------------------------------------------------
set(CMAKE_CXX_STANDARD 17)            # std::filesystem
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CUDA_STANDARD 14)

# RTX 3050 = Ampere = compute capability 8.6
if(NOT DEFINED CMAKE_CUDA_ARCHITECTURES)
  set(CMAKE_CUDA_ARCHITECTURES 86)
endif()

# silence MSVC sprintf/fopen "secure" errors used throughout the legacy code
add_definitions(-D_CRT_SECURE_NO_WARNINGS)

# ---- dependencies (installed through vcpkg) ---------------------------------
find_package(CUDAToolkit REQUIRED)
find_package(OpenGL      REQUIRED)
find_package(glfw3 CONFIG REQUIRED)
find_package(GLEW       REQUIRED)
find_package(glm   CONFIG REQUIRED)
find_package(OpenCV      REQUIRED)

# ---- sources ----------------------------------------------------------------
file(GLOB CPP_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/render/src/*.cpp")
file(GLOB CU_SOURCES  "${CMAKE_CURRENT_SOURCE_DIR}/render/src/*.cu")

add_executable(nlos_render ${CPP_SOURCES} ${CU_SOURCES})

target_include_directories(nlos_render PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/render/src"
    ${OpenCV_INCLUDE_DIRS})

target_link_libraries(nlos_render PRIVATE
    CUDA::cudart
    OpenGL::GL
    GLEW::GLEW
    glfw
    glm::glm
    ${OpenCV_LIBS})

# the renderer loads "pointlight.vertexshader" / ".fragmentshader" by RELATIVE
# path, so copy them next to the .exe after every build.
add_custom_command(TARGET nlos_render POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_CURRENT_SOURCE_DIR}/render/pointlight.vertexshader"
        "${CMAKE_CURRENT_SOURCE_DIR}/render/pointlight.fragmentshader"
        "$<TARGET_FILE_DIR:nlos_render>")
