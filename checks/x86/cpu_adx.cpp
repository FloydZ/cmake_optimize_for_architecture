#include <immintrin.h>

int main() { 
    unsigned int out = 0;
    _addcarry_u32(1, 1, 1, &out);
    return out;
}
