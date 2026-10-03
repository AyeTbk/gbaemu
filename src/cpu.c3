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

/// Read a register's value and add a constant to it if the register is PC.
fn uint Cpu.read_reg_pcadd(Cpu* cpu, uint reg, uint add) {
	if (reg != REG_PC) add = 0;
	return cpu.read_reg(reg) + add;
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

fn Cpsr Cpu.read_spsr(Cpu* cpu) {
	return *cpu.get_spsr_ptr();
}

fn Cpsr* Cpu.get_spsr_ptr(Cpu* cpu) {
	switch (cpu.cpsr.mode) {
		case CPSR_MODE_USER:
			return &cpu.cpsr; // SPSR won't be touched in user mode, so this should be fine?
		case CPSR_MODE_FIQ:
			return &cpu.spsr_fiq;
		case CPSR_MODE_SUPERVISOR:
			return &cpu.spsr_svc;
		case CPSR_MODE_ABORT:
			return &cpu.spsr_abt;
		case CPSR_MODE_IRQ:
			return &cpu.spsr_irq;
		case CPSR_MODE_UNDEFINED:
			return &cpu.spsr_und;
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
	// FIXME Pipelining effects on PC are faked, and im not sure its done well
	//       either fake them good, or simulate the pipelining.
	// FIXME Waitstates handling isnt good. waitstates need to be handled
	//       separatly between instruction code fetch and instruction data access.
	// TODO thumb mode
	fetch_decode_execute_arm(cpu, mmu);
}

fn void fetch_decode_execute_arm(Cpu* cpu, Mmu* mmu) @private {
	ArmInst inst;
	inst.raw = mmu.read32(cpu.raw_pc);
	
	if (!check_cond(inst.cond, cpu.cpsr)) {
		cpu.raw_pc += cpu.instruction_size();
		cpu.cycles += 1 + mmu.waitstates_s;
		return;
	}
	
	switch (true) {
		case inst.raw & 0xF00_0000 == 0xF00_0000: // Software Interrupt
			software_interrupt(cpu);
		case inst.raw & 0xFF0_00F0 == 0x120_0070: // Breakpoint (Abort)
			breakpoint(cpu);
		case inst.raw & 0xE00_0010 == 0xE00_0010: // Undefined (Single Data Transfer with invalid (register) shift)
			undefined_inst(inst);
		case inst.raw & 0xC00_0000 == 0x400_0000: // Single Data Transfer
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
		case inst.raw & 0xD90_0000 == 0x100_0000: // TODO PSR transfer
			unknown_inst(inst);
		case inst.raw & 0xC00_0000 == 0x000_0000: // TODO Data processing 
			data_processing(cpu, inst);
		default: unknown_inst(inst);
	}
	
	cpu.raw_pc += cpu.instruction_size();
	
	cpu.cycles += cpu.last_inst_s_cycles * (1 + mmu.waitstates_s);
	cpu.cycles += cpu.last_inst_n_cycles * (1 + mmu.waitstates_n);
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
	bitstruct dataproc : uint @overlap {
		bool op2_is_imm: 25;
		uint opcode: 21..24;
		bool set_flags: 20;
		uint rn: 16..19;
		uint rd: 12..15;
		uint op2_imm: 0..7;
		uint op2_imm_rotate_amount: 8..11;
		uint op2_shift_amount_reg: 8..11;
		uint op2_shift_amount_imm: 7..11;
		uint op2_shift_type: 5..6;
		bool op2_shift_is_reg: 4;
		uint op2_rm: 0..3;
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

fn ShiftResult shift(uint base_value, uint shift_amount, uint shift_type, Cpsr cpsr, bool is_register_shift) @private {
	ShiftResult res;
	shift_amount &= 0xFF;
	
	if (shift_amount == 0 && is_register_shift) {
		res.value = base_value;
		res.carry = cpsr.c;
		return res;
	}
	
	switch (shift_type) {
		case 0b00: // logical left
			if (shift_amount == 0) {
				res.value = base_value;
				res.carry = cpsr.c;
			} else if (shift_amount == 32) {
				res.value = base_value;
				res.carry = base_value & 1 == 1;
			} else if (shift_amount > 32) {
				res.value = 0;
				res.carry = false;
			} else {
				res.value = base_value << shift_amount;
				res.carry = (base_value & 1 << (32 - shift_amount)) != 0;
			}
		case 0b01: // logical right
			if (shift_amount == 0) shift_amount = 32;
			if (shift_amount == 32) {
				res.value = 0;
				res.carry = base_value >> 31 == 1;
			} else if (shift_amount > 32) {
				res.value = 0;
				res.carry = false;
			} else {
				res.value = base_value >> shift_amount;
				res.carry = (base_value >> (shift_amount - 1)) & 1 == 1;
			}
		case 0b10: // arithmetic right
			if (shift_amount == 0) shift_amount = 32;
			if (shift_amount >= 32) {
				res.carry = base_value >> 31 == 1;
				if (res.carry) {
					res.value = 0xFFFF_FFFF;
				} else {
					res.value = 0;
				}
			} else {
				res.value = (uint)((int)base_value >> shift_amount);
				res.carry = (base_value >> (shift_amount - 1)) & 1 == 1;
			}
		case 0b11: // rotate right
			if (shift_amount == 0) {
				// rotate right extended
				uint c_in = (uint)cpsr.c << 31;
				res.value = base_value >> 1;
				res.carry = base_value & 1 == 1;
			} else if (shift_amount == 32) {
				res.value = base_value;
				res.carry = base_value >> 31 == 1;
			} else {
				while (shift_amount > 32) {
					shift_amount -= 32;
				}
				res.value = base_value << (32 - shift_amount) | base_value >> shift_amount;
				res.carry = (base_value >> (shift_amount - 1)) & 1 == 1;
			}
		default:
			unreachable();
	}
	return res;
}

fn ShiftResult rotate_right(uint value, uint rot_amount, Cpsr cpsr) @private {
	ShiftResult res;
	res.value = value;
	res.carry = cpsr.c;
	if (rot_amount == 0) return res;
	assert(rot_amount < 32);
	
	res.value = value << (32 - rot_amount) | value >> rot_amount;
	res.carry = (value >> (rot_amount - 1)) & 1 == 1;
	return res;
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
		ShiftResult res = shift(base_offset, shift_amount, shift_type, cpu.cpsr, true);
		offset = (long)res.value;
	} else {
		offset = inst.s_dat_transfer.offset;
	}
	
	// Compute address
	uint addr = cpu.read_reg_pcadd(inst.s_dat_transfer.rn, 8);
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
			ShiftResult res = rotate_right(raw_value, rot_amount, cpu.cpsr);
			value = res.value;
		}
		cpu.write_reg(inst.s_dat_transfer.rd, value);
	} else {
		// Store
		uint value = cpu.read_reg_pcadd(inst.s_dat_transfer.rd, 12);
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

constdef OpCode : uint @private {
	AND=0x0, EOR=0x1, SUB=0x2, RSB=0x3,
	ADD=0x4, ADC=0x5, SBC=0x6, RSC=0x7,
	TST=0x8, TEQ=0x9, CMP=0xA, CMN=0xB,
	ORR=0xC, MOV=0xD, BIC=0xE, MVN=0xF,
}

fn void data_processing(Cpu* cpu, ArmInst inst) @private {
	uint pcadd;
	if (!inst.dataproc.op2_is_imm && inst.dataproc.op2_shift_amount_reg) {
		pcadd = 12;
	} else {
		pcadd = 8;
	}
	
	uint op1 = cpu.read_reg_pcadd(inst.dataproc.rn, pcadd);
	
	// Compute op2
	uint op2;
	bool shifter_carry;
	if (inst.dataproc.op2_is_imm) {
		// r-rotate imm
		uint value = inst.dataproc.op2_imm;
		uint rot_amount = inst.dataproc.op2_imm_rotate_amount * 2;
		ShiftResult res = rotate_right(value, rot_amount, cpu.cpsr);
		op2 = res.value;
		shifter_carry = res.carry;
	} else {
		// shifted reg
		uint value = cpu.read_reg_pcadd(inst.dataproc.op2_rm, pcadd);
		uint shift_amount;
		if (inst.dataproc.op2_shift_is_reg) {
			shift_amount = cpu.read_reg(inst.dataproc.op2_shift_amount_reg);
		} else {
			shift_amount = inst.dataproc.op2_shift_amount_imm;
		}
		ShiftResult res = shift(value, shift_amount, inst.dataproc.op2_shift_type, cpu.cpsr, inst.dataproc.op2_shift_is_reg);
		op2 = res.value;
		shifter_carry = res.carry;
	}
	
	// Compute value
	ulong value;
	switch ((OpCode)inst.dataproc.opcode) {
		case OpCode.AND: value = (ulong)op1 & op2;
		case OpCode.EOR: value = (ulong)op1 ^ op2;
		case OpCode.SUB: value = (ulong)op1 - op2;
		case OpCode.RSB: value = (ulong)op2 - op1;
		case OpCode.ADD: value = (ulong)op1 + op2;
		case OpCode.ADC: value = (ulong)op1 + op2 + (uint)cpu.cpsr.c;
		case OpCode.SBC: value = (ulong)op1 - op2 + (uint)cpu.cpsr.c - 1;
		case OpCode.RSC: value = (ulong)op2 - op1 + (uint)cpu.cpsr.c - 1;
		case OpCode.TST: value = (ulong)op1 & op2;
		case OpCode.TEQ: value = (ulong)op1 ^ op2;
		case OpCode.CMP: value = (ulong)op1 - op2;
		case OpCode.CMN: value = (ulong)op1 + op2;
		case OpCode.ORR: value = (ulong)op1 | op2;
		case OpCode.MOV: value = (ulong)op2;
		case OpCode.BIC: value = (ulong)op1 & ~(ulong)op2;
		case OpCode.MVN: value = ~(ulong)op2;
	}
	
	// Write value to destination reg
	bool opcode_writes_result = true;
	switch ((OpCode)inst.dataproc.opcode) {
		case OpCode.TST: case OpCode.TEQ: case OpCode.CMP: case OpCode.CMN:
			opcode_writes_result = false;
	}
	if (opcode_writes_result) {
		cpu.write_reg(inst.dataproc.rd, (uint)value);
	}
	
	bool opcode_is_logical = false;
	switch ((OpCode)inst.dataproc.opcode) {
		case OpCode.AND: case OpCode.EOR: case OpCode.TST: case OpCode.TEQ:
		case OpCode.ORR: case OpCode.MOV: case OpCode.BIC: case OpCode.MVN:
			opcode_is_logical = true;
	}
	
	// Write flags
	if (inst.dataproc.set_flags) {
		if (inst.dataproc.rd == REG_PC) {
			// Restore saved CPSR for current mode
			cpu.cpsr = cpu.read_spsr();
		} else {
			// Set flags
			if (opcode_is_logical) {
				cpu.cpsr.c = shifter_carry;
			} else {
				bool carry_in = (value >> 31) & 1 == 1;
				bool carry_out = (value >> 32) & 1 == 1;
				cpu.cpsr.v = carry_in ^ carry_out;
				cpu.cpsr.c = carry_out;
			}
			cpu.cpsr.z = value == 0;
			cpu.cpsr.n = (value >> 31) == 1;
		}
	}
	
	bool is_shift_register_specified = !inst.dataproc.op2_is_imm && inst.dataproc.op2_shift_is_reg;
	bool is_pc_written = inst.dataproc.rd == REG_PC && opcode_writes_result;
	
	cpu.last_inst_s_cycles = 1;
	cpu.last_inst_n_cycles = 0;
	cpu.last_inst_i_cycles = 0;
	if (is_shift_register_specified) {
		cpu.last_inst_i_cycles += 1;
	}
	if (is_pc_written) {
		cpu.last_inst_s_cycles += 1;
		cpu.last_inst_n_cycles += 1;
	}
}

fn void unknown_inst(ArmInst inst) @private {
	abort("unknown inst: 0x%x", inst.raw);
}
