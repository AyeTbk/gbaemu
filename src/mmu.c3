module gbaemu;

const uint MMU_ADDR_SPACE_SIZE = 256*1024*1024;
const uint MMU_ADDR_MASK = MMU_ADDR_SPACE_SIZE - 1;

struct Mmu {
	char[MMU_ADDR_SPACE_SIZE] mem;
	uint waitstates_s;
	uint waitstates_n;
}

fn void Mmu.init(Mmu* mmu) {
	// Nothing for now
}

fn uint Mmu.read32(Mmu* mmu, uint addr) {
	// limit to address space and forcibly align
	addr = addr & MMU_ADDR_MASK & (~0b11u);
	uint value = mmu.mem[addr]
		| mmu.mem[addr + 1] << 8
		| mmu.mem[addr + 2] << 16
		| mmu.mem[addr + 3] << 24;
	mmu.update_waitstates(addr);
	return value;
}

fn void Mmu.write32(Mmu* mmu, uint addr, uint value) {
	// limit to address space and forcibly align
	addr = addr & MMU_ADDR_MASK & (~0b11u);
	mmu.mem[addr] = (char)value;
	mmu.mem[addr + 1] = (char)(value >> 8);
	mmu.mem[addr + 2] = (char)(value >> 16);
	mmu.mem[addr + 3] = (char)(value >> 24);
	mmu.update_waitstates(addr);
}

fn char Mmu.read8(Mmu* mmu, uint addr) {
	// limit to address space
	addr = addr & MMU_ADDR_MASK;
	char value = mmu.mem[addr];
	mmu.update_waitstates(addr);
	return value;
}

fn void Mmu.write8(Mmu* mmu, uint addr, char value) {
	// limit to address space
	addr = addr & MMU_ADDR_MASK;
	mmu.mem[addr] = value;
	mmu.update_waitstates(addr);
}

fn void Mmu.update_waitstates(Mmu* mmu, uint addr) {
	mmu.waitstates_s = 1;
	mmu.waitstates_n = 1;
}