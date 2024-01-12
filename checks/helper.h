#include <stdint.h>
#include <inttypes.h>
#include <stdio.h>


#if defined __AVX512__ || defined __AVX512F__ || __GFNI__ || __VAES__ || __VPCLMULQDQ__
#include <immintrin.h>

typedef union _internal512_t {
	__m512i 	a;
	uint64_t 	u64[8];
	uint32_t 	u32[16];
} _internal512;

void print_m512i(const __m512i in) {
	_internal512 p;
	p.a = in;

	for (uint32_t i = 0; i < 8; i++) {
		printf("% " PRIu64 " ", p.u64[i]);
	}
	printf("\n");
}
#endif
