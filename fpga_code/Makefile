PROJ := top
PIN_DEF := icestick.pcf
DEVICE := hx1k

SIMCOMPILER := iverilog
SIMULATOR := vvp
VIEWER := gtkwave

TOPMODULE := top

SYNTHFLAGS := -p synth_ice40 -top $(TOPMODULE)
PNRFLAGS := -d $(subst hx,,$(subst lp,,$(DEVICE)))
SIMCOMPFLAGS :=
SIMFLAGS := -v

SRCS = $(wildcard *.v)
TBSRCS = $(filter %_tb.v, $(SRCS))
MODSRCS = $(filter-out %_tb.v %_incl.v, $(SRCS))
VVPS = $(patsubst %.v,%.vvp,$(TBSRCS))
VCDS = $(patsubst %_tb.v,%_wave.vcd,$(TBSRCS))

BINS := $(PROJ).bin
RPTS := $(patsubst %.bin,%.rpt,$(BINS))
BLIFS := $(patsubst %.bin,%.blif,$(BINS))
ASCS := $(patsubst %.bin,%.asc,$(BINS))

all: timing bitstream

timing: $(RPTS)

bitstream: $(BINS)

simulate: $(VCDS)

$(BLIFS): %.blif: %.v $(MODSRCS)
	yosys -Q -q '$(SYNTHFLAGS) -blif $@' $^

$(ASCS): %.asc: $(PIN_DEF) %.blif
	arachne-pnr $(PNRFLAGS) -o $@ -p $^

$(BINS): %.bin: %.asc
	icepack $< $@

$(RPTS): %.rpt: %.asc
	icetime -d $(DEVICE) -mtr $@ $<

$(VVPS): %.vvp: %.v $(MODSRCS)
	$(SIMCOMPILER) $(SIMCOMPFLAGS) $^ -o $@

$(VCDS): %_wave.vcd: %_tb.vvp
	$(SIMULATOR) $(SIMFLAGS) $<

prog: $(PROJ).bin
	iceprog $<

sudo-prog: $(PROJ).bin
	@echo 'Executing prog as root!!!'
	sudo iceprog $<

clean:
	-rm $(wildcard *.vvp) $(wildcard *.vcd) $(BLIFS) $(BINS) $(RPTS) $(ASCS)

.SECONDARY:
.PHONY: all timing bitstream simulate prog clean