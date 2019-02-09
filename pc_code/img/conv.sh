# On little endian machines (most of those out there) use rgb565be format
# to store converted raw file; SSD1331 expects data in big endian over SPI
# Otherwise, use plain rgb565
ffmpeg -i gg_small.jpeg -f rawvideo -pix_fmt rgb565be gg_small.raw

