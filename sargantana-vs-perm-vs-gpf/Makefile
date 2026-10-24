RISCV_CC ?= riscv64-unknown-elf-gcc
vsperm.elf: vsperm.S link.ld
	$(RISCV_CC) -march=rv64imah_zicsr -mabi=lp64 -nostdlib -nostartfiles -T link.ld -o $@ vsperm.S
clean:
	rm -f vsperm.elf
