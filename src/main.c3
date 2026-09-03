module gbaemu;
import std::io;

fn int main(String[] args)
{
	Mmu* mmu = mem::new(Mmu);
	Cpu cpu;
	mmu.write32(0, 777);
	cpu.r0 = mmu.read32(0);
	io::printfn("r0: %d", cpu.r0);
	fetch_decode_execute(&cpu, mmu);
	return 0;
}