__device__
void test_for_any(int value) {
    int r = __shfl_sync(0xffffffff, value,     0); 
}

int main() {

}
