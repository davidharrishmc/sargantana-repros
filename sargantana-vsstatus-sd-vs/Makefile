RISCV_CC ?= riscv64-unknown-elf-gcc
vssd.elf: vssd.S link.ld
	$(RISCV_CC) -march=rv64imafdvh_zicsr -mabi=lp64 -nostdlib -nostartfiles -T link.ld -o $@ vssd.S
clean:
	rm -f vssd.elf
