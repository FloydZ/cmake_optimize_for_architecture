#if !defined __POPCNT__
#error "__POPCNT__ define is missing"
int main() { return 0; }
#else
#include "helper.h"
#include <immintrin.h>
void test()
{
	const int out = _popcnt32(1);
	printf("%d\n", out);
}
int main() { test(); return 0; }

#endif
