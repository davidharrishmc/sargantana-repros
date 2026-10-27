RISCV_CC ?= riscv64-unknown-elf-gcc
mtval2.elf: mtval2.S harness.inc link.ld
	$(RISCV_CC) -march=rv64imah_zicsr -mabi=lp64 -nostdlib -nostartfiles -T link.ld -o $@ mtval2.S
clean:
	rm -f mtval2.elf
