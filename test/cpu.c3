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
	
	assert_eq(fx.cpu.read_reg(1), 777);
}

fn void single_data_transfer__offset_negative() @test => @pool() {
	Fx fx = make_fixture();
	
	fx.mmu.write32(0, 0xE5121010); // ldr r1, [r2, #-16]
	fx.cpu.write_reg(2, 32); // base address set to 32
	fx.mmu.write32(32-16, 666); // will expect to read 666 from addr 16 into r1
	
	gbaemu::fetch_decode_execute(&fx.cpu, fx.mmu);
	
	assert_eq(fx.cpu.read_reg(1), 666);
}

fn void single_data_transfer__offset_reg_no_shift() @test => @pool() {}
fn void single_data_transfer__offset_reg_shift_logical_left() @test => @pool() {}
fn void single_data_transfer__offset_reg_shift_logical_right() @test => @pool() {}
fn void single_data_transfer__offset_reg_shift_arithmetic_right() @test => @pool() {}
fn void single_data_transfer__offset_reg_shift_rotate_right() @test => @pool() {}

fn void single_data_transfer__preindexing_no_writeback() @test => @pool() {}
fn void single_data_transfer__preindexing_with_writeback() @test => @pool() {}
fn void single_data_transfer__postindexing_no_writeback__writebacks_anyway() @test => @pool() {}
fn void single_data_transfer__postindexing_with_writeback() @test => @pool() {}

fn void single_data_transfer__load_byte() @test => @pool() {}
fn void single_data_transfer__load_word() @test => @pool() {}
fn void single_data_transfer__load_unaligned_word() @test => @pool() {}
fn void single_data_transfer__store_byte() @test => @pool() {}
fn void single_data_transfer__store_word() @test => @pool() {}
