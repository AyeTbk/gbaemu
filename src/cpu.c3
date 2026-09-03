module gbaemu;

struct Cpu {
	uint r0;
	uint r1;
	uint r2;
	uint r3;
	uint r4;
	uint r5;
	uint r6;
	uint r7;
	uint r8;
	uint r9;
	uint r10;
	uint r11;
	uint r12;
	uint r13;
	uint r14;
	uint r15;
	uint cpsr;
	
	uint r8_fiq;
	uint r9_fiq;
	uint r10_fiq;
	uint r11_fiq;
	uint r12_fiq;
	uint r13_fiq;
	uint r14_fiq;
	uint spsr_fiq;
	
	uint r13_svc;
	uint r14_svc;
	uint spsr_svc;
	
	uint r13_abt;
	uint r14_abt;
	uint spsr_abt;
	
	uint r13_irq;
	uint r14_irq;
	uint spsr_irq;
	
	uint r13_und;
	uint r14_und;
	uint spsr_und;
}

import std::io;
fn void fetch_decode_execute(Cpu* cpu, Mmu* mmu) {
	io::printn("FDE wowee");
}