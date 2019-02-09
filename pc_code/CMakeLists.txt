cmake_minimum_required(VERSION 3.5)
project(demo LANGUAGES C)

add_subdirectory(lib_ssd1331)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Werror=format-security \
    -Werror=implicit-function-declaration -Werror=return-type")

add_executable(demo demo.c)
add_executable(send_img send_img.c)

target_link_libraries(demo ssd1331)
target_link_libraries(send_img ssd1331)