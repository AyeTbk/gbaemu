module gbaemu;

const uint REG_PC = 15;

struct Cpu {
	uint[16] r;
	Cpsr cpsr;
	
	uint r8_fiq;
	uint r9_fiq;
	uint r10_fiq;
	uint r11_fiq;
	uint r12_fiq;
	uint r13_fiq;
	uint r14_fiq;
	Cpsr spsr_fiq;
	
	uint r13_svc;
	uint r14_svc;
	Cpsr spsr_svc;
	
	uint r13_abt;
	uint r14_abt;
	Cpsr spsr_abt;
	
	uint r13_irq;
	uint r14_irq;
	Cpsr spsr_irq;
	
	uint r13_und;
	uint r14_und;
	Cpsr spsr_und;
	
	uint cycles;
	
	uint last_inst_s_cycles;
	uint last_inst_n_cycles;
	uint last_inst_i_cycles;
}

fn uint Cpu.read_reg(Cpu* cpu, uint reg) {
	// TODO impl register banking
	return cpu.r[reg & 0xf];
}

fn void Cpu.write_reg(Cpu* cpu, uint reg, uint value) {
	// TODO impl register banking
	cpu.r[reg & 0xf] = value;
}

bitstruct Cpsr : uint {
	bool n: 31; // Sign flag
	bool z: 30; // Zero flag
	bool c: 29; // Carry flag
	bool v: 28; // Overflow flag
	bool i: 7; // IRQ disable
	bool f: 6; // FIQ disable
	bool t: 5; // State bit (0=Arm, 1=Thumb)
	uint m: 0..4; // Mode bits
}

fn void fetch_decode_execute(Cpu* cpu, Mmu* mmu) {
	// TODO thumb mode
	fetch_decode_execute_arm(cpu, mmu);
}

fn void fetch_decode_execute_arm(Cpu* cpu, Mmu* mmu) @private {
	ArmInst inst;
	inst.raw = mmu.read32(cpu.read_reg(REG_PC));
	
	if (!check_cond(inst.cond, cpu.cpsr)) {
		cpu.cycles += mmu.waitstates_s;
		return;
	}
	
	switch (true) {
		case inst.raw & 0xF00_0000 == 0xF00_0000: // TODO Software Interrupt
			unknown_inst(inst);
		case inst.raw & 0xE00_0010 == 0xE00_0010: // Undefined (Single Data Transfer with invalid (register) shift)
			unknown_inst(inst);
		case inst.raw & 0xC00_0000 == 0x400_0000: // TODO Single Data Transfer
			unknown_inst(inst);
		case inst.raw & 0xE00_0000 == 0x800_0000: // TODO Block Data Transfer
			unknown_inst(inst);
		case inst.raw & 0xE00_0000 == 0xA00_0000: // TODO Branch
			unknown_inst(inst);
		case inst.raw & 0xFFF_FFF0 == 0x12F_FF10: // Branch and Exchange
			branch_and_exchange(cpu, inst.branchex.rn);
		case inst.raw & 0xFC0_00F0 == 0x000_0090: // TODO Multiply
			unknown_inst(inst);
		case inst.raw & 0xF80_00F0 == 0x080_0090: // TODO Multiply Long
			unknown_inst(inst);
		case inst.raw & 0xFB0_0FF0 == 0x100_0090: // TODO Single Data Swap
			unknown_inst(inst);
		case inst.raw & 0xE40_0F90 == 0x000_0090: // TODO Halfword Data Transfer: register offset
			unknown_inst(inst);
		case inst.raw & 0xE40_0090 == 0x040_0090: // TODO Halfword Data Transfer: immediate offset
			unknown_inst(inst);
		default: unknown_inst(inst);
	}
	
	cpu.cycles += cpu.last_inst_s_cycles * mmu.waitstates_s;
	cpu.cycles += cpu.last_inst_n_cycles * mmu.waitstates_n;
	cpu.cycles += cpu.last_inst_i_cycles;
}

fn bool check_cond(uint cond, Cpsr cpsr) @private {
	// Comments taken straight from gbatek
	switch (cond & 0xF) {
		case 0x0: return  cpsr.z; // EQ     Z=1           equal (zero) (same)
		case 0x1: return !cpsr.z; // NE     Z=0           not equal (nonzero) (not same)
		case 0x2: return  cpsr.c; // CS/HS  C=1           unsigned higher or same (carry set)
		case 0x3: return !cpsr.c; // CC/LO  C=0           unsigned lower (carry cleared)
		case 0x4: return  cpsr.n; // MI     N=1           signed negative (minus)
		case 0x5: return !cpsr.n; // PL     N=0           signed positive or zero (plus)
		case 0x6: return  cpsr.v; // VS     V=1           signed overflow (V set)
		case 0x7: return !cpsr.v; // VC     V=0           signed no overflow (V cleared)
		case 0x8: return  cpsr.c && !cpsr.z; // HI     C=1 and Z=0   unsigned higher
		case 0x9: return !cpsr.c || cpsr.z; // LS     C=0 or Z=1    unsigned lower or same
		case 0xA: return  cpsr.n == cpsr.v; // GE     N=V           signed greater or equal
		case 0xB: return  cpsr.n != cpsr.v; // LT     N<>V          signed less than
		case 0xC: return !cpsr.z && cpsr.n == cpsr.v; // GT     Z=0 and N=V   signed greater than
		case 0xD: return  cpsr.z || cpsr.n != cpsr.v; // LE     Z=1 or N<>V   signed less or equal
		case 0xE: return true; // AL     -             always (the "AL" suffix can be omitted)
		case 0xF: return false; // NV     -             never (ARMv1,v2 only) (Reserved ARMv3 and up)
	}
	unreachable("cond is a nibble, the switch covers all possible values");
}

// Instruction decoding helper
union ArmInst @private {
	uint raw;
	bitstruct : uint {
		uint cond : 28..31;
	}
	bitstruct branchex : uint {
		uint rn : 0..3;
	}
	bitstruct dataproc : uint {
		uint opcode: 21..24;
		bool s: 20;
		uint rn: 16..19;
		uint rd: 12..15;
		uint op2: 0..11;
	}
}

fn void branch_and_exchange(Cpu* cpu, uint rn) @private {
	uint rn_val = cpu.read_reg(rn);
	uint dst_addr = rn_val & ~1u;
	cpu.cpsr.t = (rn_val & 1u) == 1;
	cpu.write_reg(REG_PC, dst_addr);
	
	cpu.last_inst_s_cycles = 2;
	cpu.last_inst_n_cycles = 1;
	cpu.last_inst_i_cycles = 0;
}

fn void branch_with_maybe_link(Cpu* cpu, bool link, uint inst_offset) @private {
	abort("not implemented yet");
}

fn void unknown_inst(ArmInst inst) {
	abort("unknown inst: 0x%x", inst.raw);
}
