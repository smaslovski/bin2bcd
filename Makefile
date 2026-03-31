SRC=rtl/bin2bcd.vhd tb/tb.vhd
TB=tb_bin2bcd
OPTS=--std=93 --workdir=work
WAVE=waveforms.ghw
SAVE=waveforms.gtkw
GTKW=DISPLAY=:0 gtkwave
LOG=out.log

$(TB): $(SRC)
	mkdir -p work
	for f in $(SRC); do ghdl -a $(OPTS) $$f; done
	ghdl -e $(OPTS) $@

run: $(TB)
	ghdl -r $(OPTS) $(TB)

$(WAVE): $(TB)
	ghdl -r $(OPTS) $(TB) --wave=$@ | tee $(LOG) | tail -n5

wave: $(WAVE)
	if [ -f $(SAVE) ]; then $(GTKW) $(SAVE); else $(GTKW) $<; fi

clean:
	rm -f *.o $(TB) $(WAVE) $(LOG)
	rm -rf work

.PHONY: clean
