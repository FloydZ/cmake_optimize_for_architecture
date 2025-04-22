__device__
unsigned int test_for_funnel(unsigned int lo, unsigned int hi, unsigned int shift) {
    return __funnelshift_lc(lo, hi, shift);
}

int main() {

}
