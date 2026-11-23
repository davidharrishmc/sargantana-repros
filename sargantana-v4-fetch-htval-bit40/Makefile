RISCV_CC ?= riscv64-unknown-elf-gcc
fetchbit40.elf: fetchbit40.S mmu-harness.inc link.ld
	$(RISCV_CC) -march=rv64imah_zicsr_zicbom_zicboz -mabi=lp64 -nostdlib -nostartfiles -T link.ld -o $@ fetchbit40.S
clean:
	rm -f fetchbit40.elf
