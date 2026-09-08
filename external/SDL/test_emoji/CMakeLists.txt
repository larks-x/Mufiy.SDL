cmake_minimum_required(VERSION 3.16)
project(TestEmoji C)

set(SDL3_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../build")
set(SDL3_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../include")

add_executable(test_emoji main.c)
target_include_directories(test_emoji PRIVATE "${SDL3_INCLUDE_DIR}")
target_link_directories(test_emoji PRIVATE "${SDL3_DIR}/Release")
target_link_libraries(test_emoji SDL3)

add_custom_command(TARGET test_emoji POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${SDL3_DIR}/Release/SDL3.dll"
        "$<TARGET_FILE_DIR:test_emoji>"
    COMMENT "Copying SDL3.dll to output directory"
)
