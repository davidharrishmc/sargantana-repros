RISCV_CC ?= riscv64-unknown-elf-gcc
vuwfi.elf: vuwfi.S link.ld
	$(RISCV_CC) -march=rv64imah_zicsr -mabi=lp64 -nostdlib -nostartfiles -T link.ld -o $@ vuwfi.S
clean:
	rm -f vuwfi.elf
