RISCV_CC ?= riscv64-unknown-elf-gcc
fsdirty.elf: fsdirty.S link.ld
	$(RISCV_CC) -march=rv64imafdv_zicsr_zfa -mabi=lp64 -nostdlib -nostartfiles -T link.ld -o $@ fsdirty.S
clean:
	rm -f fsdirty.elf
