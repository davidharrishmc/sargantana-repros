RISCV_CC ?= riscv64-unknown-elf-gcc
mprvm.elf: mprvm.S mmu-harness.inc link.ld
	$(RISCV_CC) -march=rv64imah_zicsr_zicbom_zicboz -mabi=lp64 -nostdlib -nostartfiles -T link.ld -o $@ mprvm.S
clean:
	rm -f mprvm.elf
