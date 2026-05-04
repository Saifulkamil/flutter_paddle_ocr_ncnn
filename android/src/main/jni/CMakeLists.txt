project(ppocrv5ncnn)

cmake_minimum_required(VERSION 3.10)

if(NOT EXISTS "${CMAKE_SOURCE_DIR}/myfontface.h")
    execute_process(
        COMMAND ${CMAKE_COMMAND} -E tar xf "${CMAKE_SOURCE_DIR}/myfontface.zip"
        WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    )
endif()

set(OpenCV_DIR ${CMAKE_SOURCE_DIR}/opencv-mobile-4.13.0-android/sdk/native/jni)
find_package(OpenCV REQUIRED core imgproc highgui)

set(ncnn_DIR ${CMAKE_SOURCE_DIR}/ncnn-20260113-android-vulkan/${ANDROID_ABI}/lib/cmake/ncnn)
find_package(ncnn REQUIRED)

add_library(ppocrv5ncnn SHARED ppocrv5ncnn.cpp ppocrv5.cpp ndkcamera.cpp)

target_link_libraries(ppocrv5ncnn ncnn ${OpenCV_LIBS} camera2ndk mediandk)
