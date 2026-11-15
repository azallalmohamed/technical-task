// bench_isqrt: cycles per isqrt, loop overhead removed.
// Operands are generated first (so rand32() is not in the timed region), then
// the same array is processed by the software model and by the instruction.
#include "sim.h"
#include "isqrt.h"

#define N 256
static uint32_t ops[N];

int main(void) {
  printf("bench_isqrt\n");
  rand_seed(7);
  for (int i = 0; i < N; i++) ops[i] = rand32();

  uint32_t s_sw = 0, s_hw = 0, s_nop = 0;
  uint32_t c0 = rdcycle();
  for (int i = 0; i < N; i++) { uint32_t v = ops[i]; __asm__ volatile("" : "+r"(v)); s_nop += v; }  // loop + load + add overhead
  uint32_t c1 = rdcycle();
  for (int i = 0; i < N; i++) s_sw += isqrt_ref(ops[i]);
  uint32_t c2 = rdcycle();
  for (int i = 0; i < N; i++) s_hw += isqrt_hw(ops[i]);
  uint32_t c3 = rdcycle();

  uint32_t ov = (c1 - c0) / N, sw = (c2 - c1) / N, hw = (c3 - c2) / N;
  printf("loop overhead          : %u cycles/iter\n", ov);
  printf("software (with ovh)    : %u cycles/iter -> %u net\n", sw, sw - ov);
  printf("isqrt instr (with ovh) : %u cycles/iter -> %u net\n", hw, hw - ov);
  printf("speed-up (net)         : %u.%02ux ; (loop as measured) %u.%02ux\n",
         (sw - ov) / (hw - ov), ((sw - ov) * 100 / (hw - ov)) % 100, sw / hw, (sw * 100 / hw) % 100);
  CHECK_EQ("sw/hw checksum", s_hw, s_sw);
  (void)s_nop;
  return test_finish("bench_isqrt");
}
