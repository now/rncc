#include <limits.h>
#include <stddef.h>
#include <unistd.h>

#include <def.h>
#include <io-assert.h>
#include <io-in.h>

ssize_t
io_read(void *p, size_t n, struct io_in *in)
{
        require(n <= SSIZE_MAX);
        ssize_t i, r;
        for (i = 0; (size_t)i < n; i += r)
                if ((r = io_read_once((char *)p + i, n - (size_t)i, in)) < 0)
                        return r;
                else if (r == 0)
                        break;
        return i;
}
