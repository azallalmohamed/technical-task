// hw_isqrt_full: extended verification of the isqrt instruction.
//  1. boundary values: every n^2-1, n^2, n^2+1 for n = 0..65535 (exhaustive on the
//     places where floor(sqrt) changes) + 20000 random values
//  2. register aliasing: rd=rs1, rd=x0 (no write, no side effect), many rd/rs1 pairs
//  3. dependencies: isqrt after load / mul / div / csr read, result used as load
//     address, branch condition, mul operand, store data
//  4. instruction alignment: isqrt at a 2-byte-aligned (word-crossing) address
//  5. illegal encodings in custom-0 must trap (funct3 != 0, funct7 != 0, rs2 != 0,
//     other custom opcodes), with mtval = instruction word, and rd untouched
//  6. regression of existing RV32IMC behaviour next to the new unit
#include "sim.h"
#include "isqrt.h"

static volatile uint32_t mem_word = 0x00123456u;

#define ISQRT_RD_RS1(rd, rs1, in, out) \
  __asm__ volatile("mv " #rs1 ", %1\n.insn r 0x0b, 0, 0, " #rd ", " #rs1 ", x0\nmv %0, " #rd \
                   : "=r"(out) : "r"(in) : #rd, #rs1)

int main(void) {
  printf("hw_isqrt_full: extended isqrt verification\n");

  // 1. boundaries -----------------------------------------------------------
  uint32_t bad0 = g_fail_count;
  for (uint32_t n = 0; n < 65536; n++) {
    uint32_t sq = n * n;
    CHECK_EQ("isqrt(n^2)", isqrt_hw(sq), n);
    if (n > 0) CHECK_EQ("isqrt(n^2-1)", isqrt_hw(sq - 1), n - 1);
    if (n > 0 && n < 65535) CHECK_EQ("isqrt(n^2+1)", isqrt_hw(sq + 1), n);
    if (g_fail_count - bad0 > 8) break;
  }
  CHECK_EQ("isqrt(0xFFFFFFFF)", isqrt_hw(0xFFFFFFFFu), 65535);
  CHECK_EQ("isqrt(0x80000000)", isqrt_hw(0x80000000u), 46340);
  rand_seed(0xBEEF);
  for (int i = 0; i < 20000; i++) {
    uint32_t x = rand32() >> (rand32() & 31);
    CHECK_EQ("isqrt(random)", isqrt_hw(x), isqrt_ref(x));
  }
  printf("  boundaries + random done\n");

  // 2. aliasing -------------------------------------------------------------
  uint32_t r;
  ISQRT_RD_RS1(x5, x5, 123456789u, r);   CHECK_EQ("rd=rs1 x5", r, isqrt_ref(123456789u));
  ISQRT_RD_RS1(x31, x30, 0xFFFFFFFFu, r); CHECK_EQ("x31<-x30", r, 65535);
  ISQRT_RD_RS1(x6, x7, 49u, r);          CHECK_EQ("x6<-x7", r, 7);
  // rd = x0: nothing may change, and the following instruction must still run
  uint32_t keep = 0xA5A5A5A5u, after = 0;
  __asm__ volatile(".insn r 0x0b, 0, 0, x0, %1, x0\n addi %0, %0, 1"
                   : "+r"(after) : "r"(keep));
  CHECK_EQ("rd=x0 continues", after, 1);
  CHECK_EQ("rd=x0 keeps rs1", keep, 0xA5A5A5A5u);
  uint32_t z;
  __asm__ volatile(".insn r 0x0b, 0, 0, x0, %1, x0\n mv %0, x0" : "=r"(z) : "r"(1000000u));
  CHECK_EQ("x0 stays 0", z, 0);
  // rs1 = x0 -> sqrt(0)
  __asm__ volatile(".insn r 0x0b, 0, 0, %0, x0, x0" : "=r"(z));
  CHECK_EQ("isqrt x0", z, 0);

  // 3. dependencies ---------------------------------------------------------
  uint32_t m = mem_word;                                  // load -> isqrt
  CHECK_EQ("load-use", isqrt_hw(m), isqrt_ref(0x00123456u));
  uint32_t a = rand32() | 1, b = 0x10001u;
  volatile uint32_t pa = a, pb = b;
  CHECK_EQ("mul->isqrt", isqrt_hw(pa * pb), isqrt_ref(a * b));
  CHECK_EQ("div->isqrt", isqrt_hw(pa / 7u), isqrt_ref(a / 7u));
  CHECK_EQ("isqrt->mul", isqrt_hw(1000000u) * pa, 1000u * a);
  volatile uint32_t tab[8] = {10, 11, 12, 13, 14, 15, 16, 17};
  CHECK_EQ("isqrt as index", tab[isqrt_hw(49u)], 17);
  uint32_t cnt = 0;                                       // isqrt in a branch condition
  for (uint32_t i = 0; i < 20; i++)
    if (isqrt_hw(i * 7u) & 1) cnt++;
  uint32_t cnt_ref = 0;
  for (uint32_t i = 0; i < 20; i++)
    if (isqrt_ref(i * 7u) & 1) cnt_ref++;
  CHECK_EQ("branch on isqrt", cnt, cnt_ref);
  uint32_t cyc = csr_read(mcycle);                        // csr -> isqrt
  uint32_t rr = isqrt_hw(cyc);
  CHECK_EQ("csr->isqrt", rr, isqrt_ref(cyc));
  volatile uint32_t st = 0;                               // isqrt -> store -> load
  st = isqrt_hw(0x40000000u);
  CHECK_EQ("isqrt->store", st, 32768);
  uint32_t chain = 0xFFFFFFFFu;                           // long dependent chain
  for (int i = 0; i < 4; i++) chain = isqrt_hw(chain);
  CHECK_EQ("chain 65535,255,15,3", chain, 3);

  // 4. alignment: 32-bit isqrt starting at a halfword address --------------
  uint32_t u;
  __asm__ volatile(
      ".option push\n.option rvc\n"
      ".balign 4\n c.nop\n"
      ".insn r 0x0b, 0, 0, %0, %1, x0\n"       // lands on offset 2 mod 4
      ".option pop\n" : "=r"(u) : "r"(1000000u));
  CHECK_EQ("misaligned (offset 2)", u, 1000);
  __asm__ volatile(
      ".option push\n.option rvc\n"
      ".balign 4\n"
      ".insn r 0x0b, 0, 0, %0, %1, x0\n"       // offset 0
      ".option pop\n" : "=r"(u) : "r"(99999999u));
  CHECK_EQ("aligned (offset 0)", u, 9999);

  // 5. illegal encodings ----------------------------------------------------
  g_expect_illegal = 1;
  uint32_t n0;
  // rs1 = a1? use fixed: rd=a0(x10), rs1=a1(x11):  rd<<7 = 0x500, rs1<<15 = 0x58000
  // word = funct7<<25 | rs2<<20 | rs1<<15 | funct3<<12 | rd<<7 | opcode
  __asm__ volatile("li a1, 5" ::: "a1");
  g_expect_illegal = 1;
  { // funct3 = 1
    n0 = g_illegal_count; __asm__ volatile(".insn r 0x0b, 1, 0, a0, a1, x0" ::: "a0");
    CHECK_EQ("funct3=1 traps", g_illegal_count, n0 + 1);
    CHECK_EQ("funct3=1 mtval", g_last_mtval, 0x0005950bu);
    n0 = g_illegal_count; __asm__ volatile(".insn r 0x0b, 7, 0, a0, a1, x0" ::: "a0");
    CHECK_EQ("funct3=7 traps", g_illegal_count, n0 + 1);
    n0 = g_illegal_count; __asm__ volatile(".insn r 0x0b, 0, 1, a0, a1, x0" ::: "a0");
    CHECK_EQ("funct7=1 traps", g_illegal_count, n0 + 1);
    CHECK_EQ("funct7=1 mtval", g_last_mtval, 0x0205850bu);
    n0 = g_illegal_count; __asm__ volatile(".insn r 0x0b, 0, 0x40, a0, a1, x0" ::: "a0");
    CHECK_EQ("funct7=0x40 traps", g_illegal_count, n0 + 1);
    n0 = g_illegal_count; __asm__ volatile(".insn r 0x0b, 0, 0, a0, a1, a2" ::: "a0");
    CHECK_EQ("rs2=a2 traps", g_illegal_count, n0 + 1);
    n0 = g_illegal_count; __asm__ volatile(".insn r 0x0b, 0, 0, a0, a1, t6" ::: "a0");
    CHECK_EQ("rs2=x31 traps", g_illegal_count, n0 + 1);
    n0 = g_illegal_count; __asm__ volatile(".insn r 0x0b, 0, 0x7f, a0, a1, t6" ::: "a0");
    CHECK_EQ("all fields set traps", g_illegal_count, n0 + 1);
    // other custom opcodes remain illegal (custom-1 0x2b, custom-2 0x5b, custom-3 0x7b)
    n0 = g_illegal_count; __asm__ volatile(".insn r 0x2b, 0, 0, a0, a1, x0" ::: "a0");
    CHECK_EQ("custom-1 traps", g_illegal_count, n0 + 1);
    n0 = g_illegal_count; __asm__ volatile(".insn r 0x5b, 0, 0, a0, a1, x0" ::: "a0");
    CHECK_EQ("custom-2 traps", g_illegal_count, n0 + 1);
    n0 = g_illegal_count; __asm__ volatile(".insn r 0x7b, 0, 0, a0, a1, x0" ::: "a0");
    CHECK_EQ("custom-3 traps", g_illegal_count, n0 + 1);
  }
  // rd must stay untouched on an illegal encoding
  uint32_t keepd = 0x5555AAAAu;
  __asm__ volatile("mv a0, %0\n .insn r 0x0b, 1, 0, a0, a1, x0\n mv %0, a0"
                   : "+r"(keepd) :: "a0", "a1");
  CHECK_EQ("rd untouched on illegal", keepd, 0x5555AAAAu);
  // legal instruction right after an illegal one still works
  CHECK_EQ("legal after illegal", isqrt_hw(144u), 12);
  g_expect_illegal = 0;

  // 6. regression of nearby functionality -----------------------------------
  volatile int32_t s1 = -7, s2 = 3;
  CHECK_EQ("mul", (uint32_t)(s1 * s2), (uint32_t)-21);
  CHECK_EQ("div", (uint32_t)(s1 / s2), (uint32_t)-2);
  CHECK_EQ("rem", (uint32_t)(s1 % s2), (uint32_t)-1);
  volatile uint32_t u1 = 0xFFFFFFFFu, u2 = 0xFFFFFFFFu;
  CHECK_EQ("mulhu", (uint32_t)(((uint64_t)u1 * u2) >> 32), 0xFFFFFFFEu);
  CHECK_EQ("divu", u1 / 3u, 0x55555555u);
  // interleave isqrt with mul/div to make sure neither unit disturbs the other
  uint32_t acc = 0;
  for (uint32_t i = 1; i < 200; i++) {
    volatile uint32_t v = i * 12345u;
    acc += isqrt_hw(v) + v / 13u + v * 3u;
  }
  uint32_t acc_ref = 0;
  for (uint32_t i = 1; i < 200; i++) {
    uint32_t v = i * 12345u;
    acc_ref += isqrt_ref(v) + v / 13u + v * 3u;
  }
  CHECK_EQ("interleaved mul/div/isqrt", acc, acc_ref);

  return test_finish("hw_isqrt_full");
}
