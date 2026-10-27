RISCV_CC ?= riscv64-unknown-elf-gcc
gvaexc.elf: gvaexc.S harness.inc link.ld
	$(RISCV_CC) -march=rv64imah_zicsr -mabi=lp64 -nostdlib -nostartfiles -T link.ld -o $@ gvaexc.S
clean:
	rm -f gvaexc.elf
