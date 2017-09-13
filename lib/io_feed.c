#include <errno.h>
#include <limits.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include <def.h>
#include <io-in.h>
#include <io-out.h>
#include <io-buffered-in.h>

ssize_t
io_feed(struct io_out *out, struct io_in *in)
{
        char b[lengthof(fieldof(struct io_buffered_in, b))];
        ssize_t r, w, n = 0;
        while ((r = io_read(b, lengthof(b), in)) > 0 &&
               (w = io_write(out, b, (size_t)r)) > 0)
                n += r;
        if (r < 0)
                return r;
        else if (w < 0)
                return w;
        return n < SSIZE_MAX ? n : SSIZE_MAX;
}
