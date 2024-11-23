#include <immintrin.h>
#include <x86intrin.h>

int main() { 
    return _rdseed32_step(NULL);
}
