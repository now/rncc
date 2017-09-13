#include <errno.h>
#include <limits.h>
#include <stdarg.h>
#include <stddef.h>
#include <unistd.h>

#include <def.h>
#include <io-assert.h>
#include <io-in.h>
#include <io-out.h>

int
io_write(struct io_out *out, const char *s, size_t n)
{
        require(n <= SSIZE_MAX);
        ssize_t r;
        for (size_t i = 0; i < n; i += (size_t)r)
                while ((r = out->fs->write(out, s + i, n - i)) < 0)
                        if (r != -EAGAIN && r != -EINTR)
                                return require(INT_MIN <= r), (int)r;
        return 0;
}
