# ICEstick PMOD Display

Demo project for driving SSD1331 PMOD display connected to Lattice ICEstick board from PC.

## Required tools
- PC code: C compiler, make and cmake
- FPGA code: yosys, arachne_pnr, icebox tools (icepack, icetime, iceprog), iverilog, gtkwave

## Build
Don't forget to `git submodule init && git submodule update` after cloning.
- For FPGA side: `cd fpga_code` then `make all` then `make prog`
- For PC side: `cd pc_code`, `mkdir build`, `cd build`, `cmake .. && make`

## Run
- `./demo` - display some shapes on SSD1331
- `./send_img <filename>` - send picture to display. Before sending, picture must be scaled to 96x64 and the converted to RGB565 raw format (see pc_code/img folder)
