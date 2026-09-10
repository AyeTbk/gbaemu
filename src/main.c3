module gbaemu;
import std::io;

fn int main(String[] args)
{
	Mmu* mmu = mem::new(Mmu);
	Cpu cpu;
	mmu.write32(0, 0xe12fff17);
	cpu.write_reg(15, 0);
	cpu.write_reg(7, 100);
	fetch_decode_execute(&cpu, mmu);
	io::printfn("r15: %d", cpu.r[15]);
	io::printfn("cycles: %d", cpu.cycles);
	return 0;
}