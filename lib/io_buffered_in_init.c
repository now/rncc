#include <stddef.h>
#include <string.h>
#include <unistd.h>

#include <def.h>
#include <io-in.h>
#include <io-buffered-in.h>

static ssize_t
io_buffered_in_read(void *p, size_t n, struct io_in *in)
{
        struct io_buffered_in *o = (struct io_buffered_in *)in;
        size_t a = o->n - o->i;
        if (a == 0) {
                if (lengthof(o->b) < n)
                        return io_read_once(p, n, o->next);
                ssize_t r = io_read_once(o->b, lengthof(o->b), o->next);
                if (r <= 0)
                        return r;
                o->i = 0, o->n = a = (size_t)r;
        }
        size_t m = a < n ? a : n;
        memcpy(p, o->b + o->i, m);
        o->i += m;
        return (ssize_t)m;
}

static int
io_buffered_in_close(struct io_in *in)
{
        return io_in_close(((struct io_buffered_in *)in)->next);
}

const struct io_in_fns io_buffered_in_fns = {
        .read = io_buffered_in_read,
        .close = io_buffered_in_close
};

struct io_buffered_in
io_buffered_in_init(struct io_in *next)
{
        return IO_BUFFERED_IN_INIT(next);
}
