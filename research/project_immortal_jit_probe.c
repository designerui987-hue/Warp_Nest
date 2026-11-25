#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/sysctl.h>
#include <pthread.h>
#include <libkern/OSCacheControl.h>
#include <unistd.h>
#include <time.h>

int main(void) {
    int translated = -1;
    size_t size = sizeof(translated);
    if (sysctlbyname("sysctl.proc_translated", &translated, &size, NULL, 0) != 0) {
        translated = 0;
    }
    printf("proc_translated=%d (0 = native ARM64, no Rosetta)\n", translated);

    size_t page_size = (size_t)getpagesize();
    printf("host_page_size=%zu\n", page_size);

    void *buf = mmap(NULL, page_size,
                     PROT_READ | PROT_WRITE | PROT_EXEC,
                     MAP_PRIVATE | MAP_ANONYMOUS | MAP_JIT,
                     -1, 0);
    if (buf == MAP_FAILED) {
        perror("mmap(MAP_JIT) failed");
        return 1;
    }
    printf("mmap(MAP_JIT) succeeded at %p\n", buf);

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    pthread_jit_write_protect_np(0);
    uint32_t *code = (uint32_t *)buf;
    // ARM64: mov w0, #42; ret
    code[0] = 0x52800540;
    code[1] = 0xD65F03C0;
    pthread_jit_write_protect_np(1);
    sys_icache_invalidate(buf, 8);

    typedef int (*jit_fn)(void);
    jit_fn fn = (jit_fn)buf;
    int result = fn();

    clock_gettime(CLOCK_MONOTONIC, &t1);
    double elapsed_us = (t1.tv_sec - t0.tv_sec) * 1e6 + (t1.tv_nsec - t0.tv_nsec) / 1e3;

    printf("jit_fn() returned=%d (expected 42), elapsed=%.2f us\n", result, elapsed_us);
    munmap(buf, page_size);
    return (result == 42) ? 0 : 2;
}
