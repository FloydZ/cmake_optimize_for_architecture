#if !defined __LZCNT__
#error "__LZCNT__ define is missing"
int main() { return 0; }
#else
#include "helper.h"
#include <immintrin.h>
#include <stdint.h>
void test()
{
	const int out = __lzcnt64(1);
	printf("%d\n", out);
}
int main() { test(); return 0; }

#endif
