module gbaemu;

const uint REG_PC = 15;

const uint CPSR_MODE_USER = 0x10;
const uint CPSR_MODE_FIQ = 0x11;
const uint CPSR_MODE_IRQ = 0x12;
const uint CPSR_MODE_SUPERVISOR = 0x13;
const uint CPSR_MODE_ABORT = 0x17;
const uint CPSR_MODE_UNDEFINED = 0x1B;

struct Cpu {
	uint[15] r; // PC is excluded.
	Cpsr cpsr;
	
	uint raw_pc; // Program counter, without the effects of pipelining readahead.
	
	uint[15] r_fiq;
	Cpsr spsr_fiq;
	
	uint[15] r_svc;
	Cpsr spsr_svc;
	
	uint[15] r_abt;
	Cpsr spsr_abt;
	
	uint[15] r_irq;
	Cpsr spsr_irq;
	
	uint[15] r_und;
	Cpsr spsr_und;
	
	uint cycles;
	
	uint last_inst_s_cycles;
	uint last_inst_n_cycles;
	uint last_inst_i_cycles;
}

fn void Cpu.init(Cpu* cpu) {
	cpu.cpsr.mode = CPSR_MODE_USER;
}

fn uint Cpu.read_reg(Cpu* cpu, uint reg) {
	return *cpu.get_reg_ptr(reg);
}

fn void Cpu.write_reg(Cpu* cpu, uint reg, uint value) {
	*cpu.get_reg_ptr(reg) = value;
}

fn uint* Cpu.get_reg_ptr(Cpu* cpu, uint reg) {
	reg = reg & 0xf;
	if (reg == REG_PC) {
		return &cpu.raw_pc;
	}
	// Register banking
	switch (cpu.cpsr.mode) {
		case CPSR_MODE_USER:
			return &cpu.r[reg];
		case CPSR_MODE_FIQ:
			if (reg > 7) { return &cpu.r_fiq[reg]; }
			else         { return &cpu.r[reg]; }
		case CPSR_MODE_SUPERVISOR:
			if (reg > 12) { return &cpu.r_svc[reg]; }
			else          { return &cpu.r[reg]; }
		case CPSR_MODE_ABORT:
			if (reg > 12) { return &cpu.r_abt[reg]; }
			else          { return &cpu.r[reg]; }
		case CPSR_MODE_IRQ:
			if (reg > 12) { return &cpu.r_irq[reg]; }
			else          { return &cpu.r[reg]; }
		case CPSR_MODE_UNDEFINED:
			if (reg > 12) { return &cpu.r_und[reg]; }
			else          { return &cpu.r[reg]; }
	}
	abort("fellthrough unknown CPU mode");
}

fn uint Cpu.instruction_size(Cpu* cpu) {
	if (cpu.cpsr.thumb) {
		return 2;
	} else {
		return 4;
	}
}

bitstruct Cpsr : uint {
	bool n: 31; // Sign flag
	bool z: 30; // Zero flag
	bool c: 29; // Carry flag
	bool v: 28; // Overflow flag
	bool irq_disable: 7; // IRQ disable
	bool fiq_disable: 6; // FIQ disable
	bool thumb: 5; // State bit (0=Arm, 1=Thumb)
	uint mode: 0..4; // Mode bits
}

fn void fetch_decode_execute(Cpu* cpu, Mmu* mmu) {
	// TODO thumb mode
	fetch_decode_execute_arm(cpu, mmu);
}

fn void fetch_decode_execute_arm(Cpu* cpu, Mmu* mmu) @private {
	ArmInst inst;
	inst.raw = mmu.read32(cpu.raw_pc);
	cpu.raw_pc += cpu.instruction_size();
	
	if (!check_cond(inst.cond, cpu.cpsr)) {
		cpu.cycles += mmu.waitstates_s;
		return;
	}
	
	switch (true) {
		case inst.raw & 0xF00_0000 == 0xF00_0000: // Software Interrupt
			software_interrupt(cpu);
		case inst.raw & 0xFF0_00F0 == 0x120_0070: // Breakpoint (Abort)
			breakpoint(cpu);
		case inst.raw & 0xE00_0010 == 0xE00_0010: // Undefined (Single Data Transfer with invalid (register) shift)
			undefined_inst(inst);
		case inst.raw & 0xC00_0000 == 0x400_0000: // TODO Single Data Transfer
			single_data_transfer(cpu, mmu, inst);
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
	bitstruct s_dat_transfer : uint @overlap {
		bool offset_is_reg: 25; // Immediate offset (0=immediate, 1=shifted reg)
		bool pre_indexing: 24; // Pre(1)/Post(0) indexing bit
		bool add_offset: 23;  // Up(1)/Down(0) bit
		bool transfer_byte: 22; // Byte(1)/Word(0) bit
		bool write_back: 21; // Write-back bit (0=no, 1=write address into base)
		bool is_load: 20; // Load(1)/Store(0) bit
		uint rn: 16..19;
		uint rd: 12..15;
		uint offset: 0..11;
		uint shift_amount: 7..11;
		uint shift_type: 5..6;
		uint rm: 0..3;
	}
}

struct ShiftResult @private {
	bool carry;
	uint value;
}

fn ShiftResult shift(uint base_offset, uint shift_amount, uint shift_type) @private {
	ShiftResult res;
	if (shift_amount == 0) {
		res.value = base_offset;
	} else {
		switch (shift_type) {
			case 0b00: // logical left
				res.value = base_offset << shift_amount;
				res.carry = (base_offset & 1 << (32 - shift_amount)) == 1;
			case 0b01: // logical right
				res.value = base_offset >> shift_amount;
				res.carry = (base_offset & 1 << (shift_amount - 1)) == 1;
			case 0b10: // arithmetic right
				res.value = (uint)((int)base_offset >> shift_amount);
				res.carry = (base_offset & 1 << (shift_amount - 1)) == 1;
			case 0b11: // rotate right
				res.value = base_offset << (32 - shift_amount) | base_offset >> shift_amount;
				res.carry = (base_offset & 1u << 31u) == 1;
			default:
				unreachable();
		}
	}
	return res;
}

fn uint rotate_left(uint value, uint rot_amount) @private {
	if (rot_amount == 0) return value;
	return value >> (32 - rot_amount) | value << rot_amount;
}

fn void software_interrupt(Cpu* cpu) @private {
	cpu.spsr_svc = cpu.cpsr;
	cpu.cpsr.mode = CPSR_MODE_SUPERVISOR;
	cpu.cpsr.thumb = false;
	cpu.cpsr.irq_disable = true;
	
	cpu.write_reg(14, cpu.raw_pc); // TODO make sure this is indeed the address of inst after the SWI inst
	cpu.raw_pc = 0x0000_0008;
	
	cpu.last_inst_s_cycles = 2;
	cpu.last_inst_n_cycles = 1;
	cpu.last_inst_i_cycles = 0;
}

fn void breakpoint(Cpu* cpu) @private {
	cpu.spsr_abt = cpu.cpsr;
	cpu.cpsr.mode = CPSR_MODE_ABORT;
	cpu.cpsr.thumb = false;
	cpu.cpsr.irq_disable = true;
	
	cpu.write_reg(14, cpu.raw_pc); // TODO make sure this is indeed the address of inst after the BKPT inst
	cpu.raw_pc = 0x0000_000C;
	
	cpu.last_inst_s_cycles = 2;
	cpu.last_inst_n_cycles = 1;
	cpu.last_inst_i_cycles = 0;
}

fn void undefined_inst(ArmInst inst) @private {
	abort("undefined inst: 0x%x", inst.raw);
}

fn void single_data_transfer(Cpu* cpu, Mmu* mmu, ArmInst inst) @private {
	// Get offset
	long offset;
	if (inst.s_dat_transfer.offset_is_reg) {
		uint base_offset = cpu.read_reg(inst.s_dat_transfer.rm);
		uint shift_amount = inst.s_dat_transfer.shift_amount;
		uint shift_type = inst.s_dat_transfer.shift_type;
		ShiftResult res = shift(base_offset, shift_amount, shift_type);
		offset = (long)res.value;
	} else {
		offset = inst.s_dat_transfer.offset;
	}
	
	// Compute address
	uint addr = cpu.read_reg(inst.s_dat_transfer.rn);
	if (!inst.s_dat_transfer.add_offset) {
		offset = -offset;
	}
	
	// Pre-indexing
	if (inst.s_dat_transfer.pre_indexing) {
		addr = (uint)((long)addr + offset);
	}
	
	// Transfer
	if (inst.s_dat_transfer.is_load) {
		// Load
		uint value;
		if (inst.s_dat_transfer.transfer_byte) {
			value = (uint)mmu.read8(addr);
		} else {
			uint raw_value = mmu.read32(addr);
			uint rot_amount = (addr % 4) * 8;
			value = rotate_left(raw_value, rot_amount);
		}
		cpu.write_reg(inst.s_dat_transfer.rd, value);
	} else {
		// Store
		uint value = cpu.read_reg(inst.s_dat_transfer.rd);
		if (inst.s_dat_transfer.transfer_byte) {
			mmu.write8(addr, (char)(value & 0xFF));
		} else {
			mmu.write32(addr, value);
		}
	}
	
	// Post-indexing
	if (!inst.s_dat_transfer.pre_indexing) {
		addr = (uint)((long)addr + offset);
	}
	
	// Write-back address (note: write-back bit doesn't matter for post-indexing, it always writes-back)
	if (!inst.s_dat_transfer.pre_indexing || inst.s_dat_transfer.write_back) {
		cpu.write_reg(inst.s_dat_transfer.rn, addr);
	}
	
	// Set cycles
	if (inst.s_dat_transfer.is_load) {
		if (inst.s_dat_transfer.rd == REG_PC) {
			cpu.last_inst_s_cycles = 2;
			cpu.last_inst_n_cycles = 2;
			cpu.last_inst_i_cycles = 1;
		} else {
			cpu.last_inst_s_cycles = 1;
			cpu.last_inst_n_cycles = 1;
			cpu.last_inst_i_cycles = 1;
		}
	} else {
		cpu.last_inst_s_cycles = 0;
		cpu.last_inst_n_cycles = 2;
		cpu.last_inst_i_cycles = 0;
	}
}

fn void branch_and_exchange(Cpu* cpu, uint rn) @private {
	uint rn_val = cpu.read_reg(rn);
	uint dst_addr = rn_val & ~1u;
	cpu.cpsr.thumb = (rn_val & 1u) == 1;
	cpu.raw_pc = dst_addr;
	
	cpu.last_inst_s_cycles = 2;
	cpu.last_inst_n_cycles = 1;
	cpu.last_inst_i_cycles = 0;
}

fn void branch_with_maybe_link(Cpu* cpu, bool link, uint inst_offset) @private {
	abort("not implemented yet");
}

fn void unknown_inst(ArmInst inst) @private {
	abort("unknown inst: 0x%x", inst.raw);
}
