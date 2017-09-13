#include <errno.h>
#include <limits.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include <def.h>
#include <io-assert.h>
#include <io-in.h>
#include <io-out.h>

int
io_printv(struct io_out *out, const char *format, va_list args)
{
        char b[4096];
        int n = vsnprintf(b, sizeof(b), format, args);
        va_end(args);
        if (n < 0)
                return -errno;
        require((size_t)n < sizeof(b));
        return io_write(out, b, (size_t)n);
}
