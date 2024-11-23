#include <functional>

std::function<void()> f(int n) {
  return rand() ? [=,  this]() { return 1; }
                : [=, *this]() { return 2; };
}
