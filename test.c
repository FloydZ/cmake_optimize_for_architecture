#include <stdio.h>

int main() {
#ifdef USE_AVX2
	printf("AVX2\n");
#endif

#ifdef USE_AVX512
	printf("AVX512\n");
#endif

}
