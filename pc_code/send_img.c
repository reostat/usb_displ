#include <stdio.h>
#include <time.h>
#include "ssd_displ.h"

#include "ftdi_util.h"

#define exit_error(val) { \
    int __err_code__; \
    if ((__err_code__ = val) < 0) { \
        printf("Operation failed: %d, %s\n", __err_code__, ssd_get_error_string(ssd)); \
        ssd_free(ssd); \
        exit(EXIT_FAILURE); \
    } \
}

static void read_img_file(char const *file_name, uint8_t *buf, uint16_t buf_len)
{
    FILE *f = fopen(file_name, "rb");
    if (fread(buf, 1, buf_len, f) < buf_len) {
        printf("Not enough data in file %s\n", file_name);
        exit(EXIT_FAILURE);
    }
    fclose(f);
}

int main(int argc, char const *argv[])
{
    if (argc < 2) {
        printf("Specify file name\n");
        exit(EXIT_FAILURE);
    }

    // grab some mem
    size_t img_size = DISPL_WIDTH * DISPL_HEIGHT * 2;
    uint8_t *buf = malloc(img_size);
    if (buf == NULL) {
        printf("Failed to allocate %ld bytes of memory\n", img_size);
        exit(EXIT_FAILURE);
    }

    printf("Reading data from file %s\n", argv[1]);
    read_img_file(argv[1], buf, img_size);

    printf("Initializing SSD display\n");
    ssd_context *ssd = ssd_new();
    exit_error(ssd_open(ssd, 0x0403, 0x6010));

    printf("Sending data\n");;
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
