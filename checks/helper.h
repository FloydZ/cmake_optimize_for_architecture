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

#if defined __AVX2__ || defined __AVX__ || defined __AVXVNNI__ || defined __F16C__
#include <immintrin.h>
typedef union _internal256_t {
	__m256i 	a;
	uint64_t 	u64[4];
	uint32_t 	u32[8];
} _internal256;

void print_m256i(const __m256i in) {
	_internal256 p;
	p.a = in;

	for (uint32_t i = 0; i < 4; i++) {
		printf("% " PRIu64 " ", p.u64[i]);
	}
	printf("\n");
}
#endif
