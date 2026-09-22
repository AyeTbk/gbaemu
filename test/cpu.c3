module cpu_tests;

import std::io;
import std::core::string;
import gbaemu;

fn void assert_eq(uint value, uint expected) {
	if (value != expected) {
		char[1024] buf;
		String s = string::bformat(&buf, "Assertion FAILED: got %d, expected %d", value, expected);
		abort(s);
	}
}

struct Fx {
	Cpu cpu;
	Mmu* mmu;
}

fn Fx make_fixture() {
	Fx fx;
	fx.mmu = mem::tnew(Mmu);
	fx.cpu.init();
	fx.mmu.init();
	return fx;
}

fn void single_data_transfer__offset_imm() @test => @pool() {
	Fx fx = make_fixture();
	
	fx.mmu.write32(0, 0xE5921010); // ldr r1, [r2, #16]
	fx.cpu.write_reg(2, 4); // base address set to 4
	fx.mmu.write32(4+16, 777); // will expect to read 777 from addr 20 into r1
	
	gbaemu::fetch_decode_execute(&fx.cpu, fx.mmu);
	
	uint result = fx.cpu.read_reg(1);
	assert_eq(result, 777);
}

fn void single_data_transfer__offset_negative() @test => @pool() {
	Fx fx = make_fixture();
	
	fx.mmu.write32(0, 0xE5121010); // ldr r1, [r2, #-16]
	fx.cpu.write_reg(2, 32); // base address set to 32
	fx.mmu.write32(32-16, 666); // will expect to read 666 from addr 16 into r1
	
	gbaemu::fetch_decode_execute(&fx.cpu, fx.mmu);
	
	uint result = fx.cpu.read_reg(1);
	assert_eq(result, 666);
}

fn void single_data_transfer__offset_reg_no_shift() @test => @pool() {
	Fx fx = make_fixture();
	
	fx.mmu.write32(0, 0xE7921003); // ldr r1, [r2, r3]
	fx.cpu.write_reg(2, 4); // base address set to 4
	fx.cpu.write_reg(3, 16); // offset set to 16
	fx.mmu.write32(4+16, 777); // will expect to read 777 from addr 20 into r1
	
	gbaemu::fetch_decode_execute(&fx.cpu, fx.mmu);
	
	uint result = fx.cpu.read_reg(1);
	assert_eq(result, 777);
}

fn void single_data_transfer__offset_reg_shift_logical_left() @test => @pool() {
	Fx fx = make_fixture();
	
	fx.mmu.write32(0, 0xE7921183); // ldr r1, [r2, r3, LSL#3]
	fx.cpu.write_reg(2, 4); // base address set to 4
	fx.cpu.write_reg(3, 5); // value 5 left shifted by 3, offset set to 15
	fx.mmu.write32(4+5*8, 777); // will expect to read 777 from addr 44 into r1
	
	gbaemu::fetch_decode_execute(&fx.cpu, fx.mmu);
	
	uint result = fx.cpu.read_reg(1);
	assert_eq(result, 777);
}

fn void single_data_transfer__offset_reg_shift_logical_right() @test => @pool() {
	Fx fx = make_fixture();
	
	fx.mmu.write32(0, 0xE79211a3); // ldr r1, [r2, r3, LSR#8]
	fx.cpu.write_reg(2, 4); // base address set to 4
	fx.cpu.write_reg(3, 36); // value 36 right shifted by 3, offset set to 4
	fx.mmu.write32(4+36/8, 777); // will expect to read 777 from addr 8 into r1
	
	gbaemu::fetch_decode_execute(&fx.cpu, fx.mmu);
	
	uint result = fx.cpu.read_reg(1);
	assert_eq(result, 777);
}

fn void single_data_transfer__offset_reg_shift_arithmetic_right() @test => @pool() {
	Fx fx = make_fixture();
	
	fx.mmu.write32(0, 0xE79211c3); // ldr r1, [r2, r3, ASR#3]
	fx.cpu.write_reg(2, 24); // base address set to 24
	fx.cpu.write_reg(3, 0xFFFFFFE7); // offset set to a mess that boils down to -4
	fx.mmu.write32(24-4, 777); // will expect to read 777 from addr 20 into r1
	
	gbaemu::fetch_decode_execute(&fx.cpu, fx.mmu);
	
	uint result = fx.cpu.read_reg(1);
	assert_eq(result, 777);
}

fn void single_data_transfer__offset_reg_shift_rotate_right() @test => @pool() {
	Fx fx = make_fixture();
	
	fx.mmu.write32(0, 0xE7921003); // ldr r1, [r2, r3, ROR#29]
	fx.cpu.write_reg(2, 4); // base address set to 4
	fx.cpu.write_reg(3, 24); // offset set to a mess that boils down to 24
	fx.mmu.write32(4+24, 777); // will expect to read 777 from addr 28 into r1
	
	gbaemu::fetch_decode_execute(&fx.cpu, fx.mmu);
	
	uint result = fx.cpu.read_reg(1);
	assert_eq(result, 777);
}

fn void single_data_transfer__offset_reg_shift__cpsr_is_unaffected() @test => @pool() {
	Fx fx = make_fixture();
	
	fx.mmu.write32(0, 0xE7921003); // ldr r1, [r2, r3, ROR#29]
	fx.cpu.write_reg(2, 4); // base address set to 4
	fx.cpu.write_reg(3, 24); // offset set to a mess that boils down to 24
	fx.mmu.write32(4+24, 777); // will expect to read 777 from addr 28 into r1
	Cpsr initial_cpsr = fx.cpu.cpsr;
	
	gbaemu::fetch_decode_execute(&fx.cpu, fx.mmu);
	
	Cpsr result = fx.cpu.cpsr;
	assert_eq((uint)result, (uint)initial_cpsr);
}

fn void single_data_transfer__preindexing_no_writeback() @test => @pool() {
	Fx fx = make_fixture();
	
	fx.mmu.write32(0, 0xE5921010); // ldr r1, [r2, #16]
	fx.cpu.write_reg(2, 4); // base address set to 4
	// Will expect base address to remain 4 after execution (no writeback)
	
	gbaemu::fetch_decode_execute(&fx.cpu, fx.mmu);
	
	uint result = fx.cpu.read_reg(2);
	assert_eq(result, 4);
}

fn void single_data_transfer__preindexing_with_writeback() @test => @pool() {
	Fx fx = make_fixture();
	
	fx.mmu.write32(0, 0xE5B21010); // ldr r1, [r2, #16]!
	fx.cpu.write_reg(2, 4); // base address set to 4
	// Will expect base address to become 4+16 after execution (because writeback)
	
	gbaemu::fetch_decode_execute(&fx.cpu, fx.mmu);
	
	uint result = fx.cpu.read_reg(2);
	assert_eq(result, 20);
}

fn void single_data_transfer__postindexing_no_writeback__writebacks_anyway() @test => @pool() {
	Fx fx = make_fixture();
	
	fx.mmu.write32(0, 0xE4921010); // ldr r1, [r2], #16
	fx.cpu.write_reg(2, 4); // base address set to 4
	// Will expect base address to become 4+16 after execution (despite no writeback)
	
	gbaemu::fetch_decode_execute(&fx.cpu, fx.mmu);
	
	uint result = fx.cpu.read_reg(2);
	assert_eq(result, 20);
}

fn void single_data_transfer__postindexing_with_writeback() @test => @pool() {
	// NOTE: It is unclear to me whether the GBA actually supports this. The data sheet says
	//       that this is used to encode a non-priviledged transfer, when in a priviledged
	//       mode of execution.
	Fx fx = make_fixture();
	
	fx.mmu.write32(0, 0xE4B21010); // ldr r1, [r2], #16   with writeback bit = 1
	fx.cpu.write_reg(2, 4); // base address set to 4
	// Will expect base address to become 4+16 after execution (because writeback)
	
	gbaemu::fetch_decode_execute(&fx.cpu, fx.mmu);
	
	uint result = fx.cpu.read_reg(2);
	assert_eq(result, 20);
}

fn void single_data_transfer__load_byte() @test => @pool() {
	Fx fx = make_fixture();
	
	fx.mmu.write32(0, 0xE5D21000); // ldrb r1, [r2]
	fx.cpu.write_reg(2, 20); // base address set to 20
	fx.mmu.write32(20, 248); // will expect to read 248 into r1
	
	gbaemu::fetch_decode_execute(&fx.cpu, fx.mmu);
	
	uint result = fx.cpu.read_reg(1);
	assert_eq(result, 248);
}

fn void single_data_transfer__load_word() @test => @pool() {
	Fx fx = make_fixture();
	
	fx.mmu.write32(0, 0xE5921000); // ldr r1, [r2]
	fx.cpu.write_reg(2, 20); // base address set to 20
	fx.mmu.write32(20, 0xBEEF_CAFE); // will expect to read 0xBEEF_CAFE into r1
	
	gbaemu::fetch_decode_execute(&fx.cpu, fx.mmu);
	
	uint result = fx.cpu.read_reg(1);
	assert_eq(result, 0xBEEF_CAFE);
}

fn void single_data_transfer__load_unaligned_word() @test => @pool() {
	Fx fx = make_fixture();
	
	fx.mmu.write32(0, 0xE5923000); // ldr r3, [r2]
	fx.mmu.write32(4, 0xE5924001); // ldr r4, [r2, #1]
	fx.mmu.write32(8, 0xE5925002); // ldr r5, [r2, #2]
	fx.mmu.write32(12, 0xE5926003); // ldr r6, [r2, #3]
	fx.cpu.write_reg(2, 20); // base address set to 20
	fx.mmu.write32(20, 0xABCD_EF09);
	
	gbaemu::fetch_decode_execute(&fx.cpu, fx.mmu);
	gbaemu::fetch_decode_execute(&fx.cpu, fx.mmu);
	gbaemu::fetch_decode_execute(&fx.cpu, fx.mmu);
	gbaemu::fetch_decode_execute(&fx.cpu, fx.mmu);
	
	uint result3 = fx.cpu.read_reg(3);
	uint result4 = fx.cpu.read_reg(4);
	uint result5 = fx.cpu.read_reg(5);
	uint result6 = fx.cpu.read_reg(6);
	assert_eq(result3, 0xABCD_EF09);
	assert_eq(result4, 0x09AB_CDEF);
	assert_eq(result5, 0xEF09_ABCD);
	assert_eq(result6, 0xCDEF_09AB);
}

fn void single_data_transfer__store_byte() @test => @pool() {
	Fx fx = make_fixture();
	
	fx.mmu.write32(0, 0xE5C21000); // strb r1, [r2]
	fx.cpu.write_reg(1, 0xFFFF_FFAB);
	fx.cpu.write_reg(2, 20);
	// will expect to store 0xAB at addr 20, nothing else
	
	gbaemu::fetch_decode_execute(&fx.cpu, fx.mmu);
	
	uint result = fx.mmu.read32(20);
	assert_eq(result, 0xAB);
}

fn void single_data_transfer__store_word() @test => @pool() {
	Fx fx = make_fixture();
	
	fx.mmu.write32(0, 0xE5821000); // str r1, [r2]
	fx.cpu.write_reg(1, 0x89AB_CDEF);
	fx.cpu.write_reg(2, 20);
	// will expect to store 0x89AB_CDEF at addr 20..23
	
	gbaemu::fetch_decode_execute(&fx.cpu, fx.mmu);
	
	uint result = fx.mmu.read32(20);
	assert_eq(result, 0x89AB_CDEF);
}

// NOTE: A bunch of shifts tests are done in the single_data_transfer tests
fn void data_transfer__op2_reg_shift_by_32_or_more() @test => @pool() {
	// TODO
	// see arm7tdmi data sheet, page 4-15
	// there's like 7 test cases to impl
}

fn void data_transfer__op2_reg_shift_by_0_special_meaning() @test => @pool() {
	// TODO
	// see arm7tdmi data sheet, pages 4-13, 4-14
	// thats maybe 4 test cases to impl
}
