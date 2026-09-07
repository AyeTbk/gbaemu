module gbaemu;
import std::io;

fn int main(String[] args)
{
	Mmu* mmu = mem::new(Mmu);
	Cpu cpu;
	mmu.write32(0, 0x12fff17);
	cpu.write_reg(15, 87);
	fetch_decode_execute(&cpu, mmu);
	io::printfn("r15: %d", cpu.r[15]);
	return 0;
}