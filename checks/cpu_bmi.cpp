#if !defined __BMI__
#error "__BMI__ define is missing"
int main() { return 0; }
#else
#include "helper.h"
#include <immintrin.h>
void test()
{
	const int out = __tzcnt_u64(1ul);
	printf("%d\n", out);
}
int main() { test(); return 0; }

#endif
