set(CMAKE_FOLDER ThirdParty)

include(FetchContent)

# Google Abseil C++ Library
FetchContent_Declare(
    abseil
    GIT_REPOSITORY https://github.com/abseil/abseil-cpp
    GIT_TAG 997aaf3a28308eba1b9156aa35ab7bca9688e9f6
)

# Google Protobuf
FetchContent_Declare(
    protobuf
    GIT_REPOSITORY https://github.com/protocolbuffers/protobuf.git
    GIT_TAG v3.19.3
    SOURCE_SUBDIR cmake
)
set(protobuf_BUILD_TESTS OFF)

# TensorFlow python package
if(WIN32)
    FetchContent_Declare(
        tensorflow_whl
        URL https://files.pythonhosted.org/packages/36/65/e0eebf64df8d1e7b1575b7ccee6e527d96ac1093297a153df488077f0743/tensorflow_cpu-2.7.0-cp37-cp37m-win_amd64.whl
        URL_HASH SHA256=b4e2a9c1104f1210b53641937b286d1259b351ba915d9812d8948a664561d4a3
    )
else()
    FetchContent_Declare(
        tensorflow_whl
        URL https://files.pythonhosted.org/packages/2d/5c/417ca2f34e63b5681e61d300f4358d838b6720a1a669aa48fca9eab68371/tensorflow_cpu-2.7.0-cp37-cp37m-manylinux2010_x86_64.whl
        URL_HASH SHA256=a043c8185889c17e6577b26b05c614d2ebfe44c84b5a168a90ab2f1762263cc7
    )
endif()

# DirectX-Headers repo
FetchContent_Declare(
    directx_headers
    GIT_REPOSITORY https://github.com/microsoft/DirectX-Headers
    GIT_TAG d49ae12ab350b20468a9667bad700f3227cd3f7a
)

# DirectML Redistributable NuGet package
FetchContent_Declare(
    directml_redist
    URL https://www.nuget.org/api/v2/package/Microsoft.AI.DirectML/1.7.0
    URL_HASH SHA256=77bd5de862c36f084c138ff3341936dca01bd21e58bfc57cb45118b116b1f9f4
)

# DirectMLX helper library
FetchContent_Declare(
    directmlx
    URL https://raw.githubusercontent.com/microsoft/DirectML/36a8fcbac70fecb9f451a4e617d48ad3780de6cb/Libraries/DirectMLX.h
    URL_HASH SHA256=d57487c96d63f58d2780dfa128817f387b8e4cb4655d851815c3b8ec51c5dd14
    DOWNLOAD_NO_EXTRACT TRUE
)

# WinPixEventRuntime NuGet package
FetchContent_Declare(
    pix_event_runtime
    URL https://www.nuget.org/api/v2/package/WinPixEventRuntime/1.0.210209001
    URL_HASH SHA256=ee0af78308ea90c31b0c2a0c8814d2bef994e4cbfb5ae6c5b98b50c7fd98e1bc
)

# Download and extract dependencies.
FetchContent_MakeAvailable(
    abseil
    protobuf
    tensorflow_whl
    directx_headers
    directml_redist 
    directmlx
    pix_event_runtime
)

# The DirectX-Headers target assumes dependent targets include headers with the directx prefix 
# (e.g. <directx/d3d12.h>). However, directml.h unconditionally includes "d3d12.h"; this works on
# Windows with the SDK installed, but WSL builds need to resolve this include correctly.
target_include_directories(DirectX-Headers INTERFACE ${directx_headers_SOURCE_DIR}/include/directx)

# Target to add DirectML redist headers to the include path.
add_library(directml_headers INTERFACE)
target_include_directories(directml_headers INTERFACE ${directml_redist_SOURCE_DIR}/include)
add_library(directml_redist::headers ALIAS directml_headers)

# Target to add DirectMLX headers to the include path.
add_library(directmlx_headers INTERFACE)
target_include_directories(directmlx_headers INTERFACE ${directmlx_SOURCE_DIR})
add_library(directmlx::headers ALIAS directmlx_headers)

# Target (for convenience) that adds both DirectML and DirectMLX headers to the include path.
add_library(directml_all_headers INTERFACE)
target_link_libraries(directml_all_headers INTERFACE directml_headers directmlx_headers)
add_library(directml::headers ALIAS directml_all_headers)

# Target to add WinPixEventRuntime headers to the include path.
add_library(pix_headers INTERFACE)
target_include_directories(pix_headers INTERFACE ${pix_event_runtime_SOURCE_DIR}/include)
add_library(pix_event_runtime::headers ALIAS pix_headers)

# Location to generate .pb.h/.pb.cc files from the packaged TF .proto files. The TF wheel
# comes with pre-generated .pb.h files, but we need the source files (not included) when linking.
# This script uses the protobuf dependency above to regenerate C++ code for the .proto files 
# needed by the TFDML plugin. The .pb.h files and protobuf headers in the TF wheel are intentionally
# deleted to avoid accidental usage, since their protobuf version will not likely match the copy
# of protobuf above.
set(tensorflow_generated_protobuf_dir ${tensorflow_whl_BINARY_DIR}/proto)
set(tensorflow_include_dir ${tensorflow_whl_SOURCE_DIR}/tensorflow/include)
file(GLOB_RECURSE tensorflow_whl_pb_h_files ${tensorflow_include_dir}/**/*.pb.h)
if(tensorflow_whl_pb_h_files)
    file(REMOVE ${tensorflow_whl_pb_h_files})
endif()
file(REMOVE_RECURSE ${tensorflow_include_dir}/google/protobuf)

# Target to add TensorFlow headers, generated .pb.h files, and runtime lib. The runtime lib
# contains symbols for the plugin APIs and a few utilities (e.g. logging).
add_library(tensorflow_whl_lib STATIC)
target_include_directories(
    tensorflow_whl_lib 
    PUBLIC
    ${tensorflow_generated_protobuf_dir}
    $<TARGET_PROPERTY:libprotobuf,INCLUDE_DIRECTORIES>
    INTERFACE 
    ${tensorflow_whl_SOURCE_DIR}/tensorflow/include
)
target_link_libraries(
    tensorflow_whl_lib 
    INTERFACE 
    $<$<BOOL:${WIN32}>:${tensorflow_whl_SOURCE_DIR}/tensorflow/python/_pywrap_tensorflow_internal.lib>
    $<$<BOOL:${UNIX}>:${tensorflow_whl_SOURCE_DIR}/tensorflow/libtensorflow_framework.so.2>
    libprotobuf
)
add_library(tensorflow_whl::lib ALIAS tensorflow_whl_lib)

# Introduces a command to generate C++ code for a .proto file in the TF wheel.
function(tf_proto_cpp proto_path)
    cmake_path(GET proto_path STEM proto_stem)
    cmake_path(GET proto_path PARENT_PATH proto_parent_dir)
    cmake_path(SET proto_generated_h ${tensorflow_generated_protobuf_dir}/${proto_parent_dir}/${proto_stem}.pb.h)
    cmake_path(SET proto_generated_cc ${tensorflow_generated_protobuf_dir}/${proto_parent_dir}/${proto_stem}.pb.cc)

    add_custom_command(
        OUTPUT 
            ${proto_generated_h} 
            ${proto_generated_cc}
        COMMAND 
            protobuf::protoc 
            --proto_path=${tensorflow_include_dir}
            --cpp_out=${tensorflow_generated_protobuf_dir} 
            ${proto_path}
        DEPENDS
            ${tensorflow_include_dir}/${proto_path}
        COMMENT
            "Generating C++ code for ${proto_path}"
    )

    target_sources(tensorflow_whl_lib PRIVATE ${proto_generated_h} ${proto_generated_cc})
endfunction()

# Generate the necessary .proto files in the TF wheel (performed at build time).
tf_proto_cpp(tensorflow/core/framework/resource_handle.proto)
tf_proto_cpp(tensorflow/core/framework/tensor.proto)
tf_proto_cpp(tensorflow/core/framework/tensor_shape.proto)
tf_proto_cpp(tensorflow/core/framework/types.proto)
tf_proto_cpp(tensorflow/core/profiler/protobuf/xplane.proto)

# A python interpreter is required to produce the plugin wheel. This python environment
# must have the 'wheel' package installed.
find_package(Python 3.6 COMPONENTS Interpreter REQUIRED)

execute_process(
    COMMAND "${Python_EXECUTABLE}" "-c" "import wheel"
    RESULT_VARIABLE python_wheel_check_exit_code
    OUTPUT_QUIET
)
if(NOT ${python_wheel_check_exit_code} EQUAL 0)
    message(
        FATAL_ERROR 
        "The python interpreter at '${Python_EXECUTABLE}' does not "
        "have the 'wheel' package installed."
    )
endif()

set(CMAKE_FOLDER "")