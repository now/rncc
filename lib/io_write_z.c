#include <limits.h>
#include <stdarg.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>

#include <def.h>
#include <io-assert.h>
#include <io-in.h>
#include <io-out.h>

int
io_write_z(struct io_out *out, const char *s)
{
        size_t n = strlen(s);
        require(n <= SSIZE_MAX);
        return io_write(out, s, n);
}
