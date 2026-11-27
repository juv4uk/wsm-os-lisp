#include <stdint.h>
#include <stdio.h>

int main(void) {
    uint64_t sum = 0;
    for (uint64_t i = 1; i <= 1000000; ++i) {
        sum += (i * 17u) % 97u;
    }
    printf("result=%llu\n", (unsigned long long)sum);
    return 0;
}
