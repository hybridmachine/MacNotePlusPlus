cmake_minimum_required(VERSION 3.20)
project(HelloPaperWasp LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)

add_library(HelloPaperWasp MODULE HelloPaperWasp.cpp)

set_target_properties(HelloPaperWasp PROPERTIES
    PREFIX ""
    SUFFIX ".dylib"
    OUTPUT_NAME "HelloPaperWasp"
)

# Allow unresolved symbols that the host app provides at load time
target_link_options(HelloPaperWasp PRIVATE
    "LINKER:-undefined,dynamic_lookup"
)
