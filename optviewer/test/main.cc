#include <iostream>
#include <vector>
#include <cstdint>


#define N 20000

void scale_down(std::vector<double>& v,
                const double& a) noexcept {
    for (auto& item : v) {
        item /= a;
    }
}

double scale_down_example() {
    std::vector<double> v; v.resize(N);
    for (size_t i = 0; i < N; i++) {
        v[i] = ((double)rand())/((double)(1ull<<32u));
    }
 
    double ret = 0.0;
    for (size_t i = 0; i < N; i++) {
        scale_down(v, v[i]);
        ret += v[i];
    }
    
    return ret;
}

int main() {
    return (int)scale_down_example();
}
