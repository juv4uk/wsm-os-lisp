#include <stddef.h>
#include <stdint.h>

typedef int32_t (*probe_callback)(int32_t value, void *context);

struct probe_record {
    int32_t tag;
    uint64_t value;
};

_Static_assert(offsetof(struct probe_record, value) == 8,
               "probe_record.value ABI offset changed");
_Static_assert(sizeof(struct probe_record) == 16,
               "probe_record ABI size changed");

int32_t c_mix(int32_t left, int32_t right) {
    return (left * 31) ^ (right + 7);
}

uint64_t c_probe_record_size(void) {
    return (uint64_t)sizeof(struct probe_record);
}

uint64_t c_probe_record_value_offset(void) {
    return (uint64_t)offsetof(struct probe_record, value);
}

/*
 * record and context are borrowed for this call only.
 * C retains neither pointer and allocates/frees no caller-owned memory.
 */
int32_t c_record_transform(struct probe_record *record,
                           probe_callback callback,
                           void *context) {
    if (record == NULL || callback == NULL || context == NULL) {
        return -1;
    }
    record->value += UINT64_C(7);
    return callback(record->tag, context);
}
