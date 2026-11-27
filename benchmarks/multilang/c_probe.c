#include <stdint.h>

int32_t c_mix(int32_t left, int32_t right) {
    return (left * 31) ^ (right + 7);
}
