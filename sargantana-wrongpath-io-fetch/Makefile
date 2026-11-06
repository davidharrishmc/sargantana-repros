RISCV_CC ?= riscv64-unknown-elf-gcc
wpfetch.elf: wpfetch.S link.ld
	$(RISCV_CC) -march=rv64i -mabi=lp64 -nostdlib -nostartfiles -T link.ld -o $@ wpfetch.S
clean:
	rm -f wpfetch.elf
