RISCV_CC ?= riscv64-unknown-elf-gcc
gva.elf: gva.S link.ld
	$(RISCV_CC) -march=rv64imah_zicsr -mabi=lp64 -nostdlib -nostartfiles -T link.ld -o $@ gva.S
clean:
	rm -f gva.elf
