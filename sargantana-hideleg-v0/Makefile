RISCV_CC ?= riscv64-unknown-elf-gcc
hideleg.elf: hideleg.S link.ld
	$(RISCV_CC) -march=rv64imah_zicsr -mabi=lp64 -nostdlib -nostartfiles -T link.ld -o $@ hideleg.S
clean:
	rm -f hideleg.elf
