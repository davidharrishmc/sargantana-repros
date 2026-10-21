RISCV_CC ?= riscv64-unknown-elf-gcc
lcofi.elf: lcofi.S link.ld
	$(RISCV_CC) -march=rv64imah_zicsr -mabi=lp64 -nostdlib -nostartfiles -T link.ld -o $@ lcofi.S
clean:
	rm -f lcofi.elf
