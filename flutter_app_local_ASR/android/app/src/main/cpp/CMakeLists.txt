cmake_minimum_required(VERSION 3.22.1)

project(local_meeting_asr LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(WHISPER_ALL_WARNINGS OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)

add_subdirectory(third_party/whisper.cpp)

add_library(local_meeting_asr SHARED
    native_bridge.cpp
)

target_include_directories(local_meeting_asr PRIVATE
    third_party/whisper.cpp/include
)

target_link_libraries(local_meeting_asr PRIVATE
    whisper
    android
    log
)
