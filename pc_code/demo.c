#include <stdio.h>
#include <time.h>
#include "ssd_displ.h"
#include "ssd_displ_graph.h"

#include "ftdi_util.h"

#define exit_error(val) { \
    int __err_code__; \
    if ((__err_code__ = val) < 0) { \
        printf("Operation failed: %d, %s\n", __err_code__, ssd_get_error_string(ssd)); \
        ssd_free(ssd); \
        exit(EXIT_FAILURE); \
    } \
}

static color565_t get_point_color(point_t const *point)
{
    color565_t colors[3];
    set_color(colors, 0x1F, 0, 0);
    set_color(colors + 1, 0, 0x0, 0);
    set_color(colors + 2, 0, 0, 0x1F);
    return colors[point->y % 3];
}

static void to_bytes(color565_t color, uint8_t *bytes)
{
    uint16_t col = ((color.r & 0x1F) << 11) | ((color.g & 0x3F) << 5) | (color.b & 0x1F);
    //printf("col 0x%04X\n", col);
    bytes[0] = col >> 8;
    bytes[1] = col & 0xFF;
}

int main(int argc, char const *argv[])
{
    printf("Initializing SSD display\n");
    ssd_context *ssd = ssd_new();
    exit_error(ssd_open(ssd, 0x0403, 0x6010));

    line_t line = {{0,0}, {MAX_X,0}};
    color565_t color = {0x1F, 0x0, 0x0};

    for(int i = 0; i <= MAX_Y; i++) {
        line.start.y = i;
        line.end.y = MAX_Y - i;
        color.b = i;
        exit_error(ssd_clear_display(ssd));
        exit_error(ssd_draw_line(ssd, &line, &color));
        usleep(100000);
    }
    exit_error(ssd_clear_display(ssd));

    usleep(200000);
    set_color(&color, 0x10, 0x0, 0x0);
    set_line(&line, 0, 0, 31, MAX_Y);
    exit_error(ssd_draw_box(ssd, &line, &color, &color));
    sleep(2);
    set_color(&color, 0x1F, 0x3F, 0x1F);
    set_line(&line, 32, 0, 63, MAX_Y);
    exit_error(ssd_draw_box(ssd, &line, &color, &color));
    sleep(2);
    set_color(&color, 0x0, 0x0, 0x10);
    set_line(&line, 64, 0, 95, MAX_Y);
    exit_error(ssd_draw_box(ssd, &line, &color, &color));
    sleep(2);
    exit_error(ssd_clear_display(ssd));

    printf("Sending data\n");
    point_t point = {0,0};
    uint8_t bytes[2];
    exit_error(ssd_begin_pixel_transfer(ssd));
    for (int y = 0; y <= MAX_Y; y++) {
        for (int x = 0; x <= MAX_X; x++) {
            point.x = x; point.y = y;
            to_bytes(get_point_color(&point), bytes);
            exit_error(ssd_send_pixels(ssd, bytes, 2));
        }
    }
    exit_error(ssd_end_transfer(ssd));
    exit_error(ssd_clear_display(ssd));
    sleep(2);

    printf("Sending data in batch\n");
    uint8_t *buf = malloc(DISPL_WIDTH * DISPL_HEIGHT * 2);
    if (buf == NULL) {
        printf("Failed to allocate batch\n");
        ssd_free(ssd);
        exit(EXIT_FAILURE);
    }
    uint8_t *buf_ptr = buf;
    for (int y = 0; y <= MAX_Y; y++) {
        for (int x = 0; x <= MAX_X; x++) {
            point.x = x; point.y = y;
            to_bytes(get_point_color(&point), buf_ptr);
            buf_ptr += 2;
        }
    }

    exit_error(ssd_begin_pixel_transfer(ssd));
    clock_t t = clock();
    exit_error(ssd_send_pixels(ssd, buf, DISPL_WIDTH * DISPL_HEIGHT * 2));
    t = clock() - t;
    exit_error(ssd_end_transfer(ssd));
    double time = ((double) t) / (CLOCKS_PER_SEC / 1000);
    printf("Batch transfer took %f ms\n", time);

    free(buf);

    printf("Releasing SSD display\n");
    ssd_free(ssd);
    return 0;
}
