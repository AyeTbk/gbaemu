module gbaemu;
import std::io;

fn int main(String[] args)
{
	Mmu* mmu = mem::new(Mmu);
	
	Cpu cpu;
	cpu.init();
	
	mmu.write32(0, 0xe12fff17);
	cpu.write_reg(15, 0);
	cpu.write_reg(7, 100);
	fetch_decode_execute(&cpu, mmu);
	io::printfn("r15: %d", cpu.raw_pc);
	io::printfn("cycles: %d", cpu.cycles);
	
	cpu.cpsr.mode = CPSR_MODE_UNDEFINED;
	cpu.write_reg(14, 777);
	io::printfn("r14_und: %d", cpu.read_reg(14));
	cpu.cpsr.mode = CPSR_MODE_USER;
	io::printfn("r14: %d", cpu.read_reg(14));
	
	return 0;
}