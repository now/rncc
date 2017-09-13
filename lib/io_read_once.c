#include <errno.h>
#include <limits.h>
#include <stddef.h>
#include <unistd.h>

#include <def.h>
#include <io-assert.h>
#include <io-in.h>

ssize_t
io_read_once(void *p, size_t n, struct io_in *in)
{
        require(n <= SSIZE_MAX);
        ssize_t r;
        while ((r = in->fs->read(p, n, in)) < 0)
                if (r != -EAGAIN && r != -EINTR)
                        return require(INT_MIN <= r), (int)r;
        return r;
}
