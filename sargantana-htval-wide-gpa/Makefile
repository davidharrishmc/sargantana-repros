RISCV_CC ?= riscv64-unknown-elf-gcc
htvalwide.elf: htvalwide.S mmu-harness.inc link.ld
	$(RISCV_CC) -march=rv64imah_zicsr_zicbom_zicboz -mabi=lp64 -nostdlib -nostartfiles -T link.ld -o $@ htvalwide.S
clean:
	rm -f htvalwide.elf
