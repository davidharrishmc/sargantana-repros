RISCV_CC ?= riscv64-unknown-elf-gcc
tvm.elf: tvm.S harness.inc link.ld
	$(RISCV_CC) -march=rv64imah_zicsr -mabi=lp64 -nostdlib -nostartfiles -T link.ld -o $@ tvm.S
clean:
	rm -f tvm.elf
