#include <stdarg.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>

#include <def.h>
#include <io-in.h>
#include <io-out.h>
#include <io-buffered-out.h>

static int
flush(struct io_buffered_out *o)
{
        int r = io_write(o->next, o->b, o->n);
        o->n = 0;
        return r;
}

static ssize_t
io_buffered_out_write(struct io_out *out, const char *s, size_t n)
{
        struct io_buffered_out *o = (struct io_buffered_out *)out;
        int r;
        if (o->n == sizeof(o->b) && (r = flush(o) < 0))
                return r;
        size_t m = sizeof(o->b) - o->n < n ? sizeof(o->b) - o->n : n;
        memcpy(o->b + o->n, s, m);
        o->n += m;
        return (ssize_t)m;
}

static int
io_buffered_out_close(struct io_out *out)
{
        struct io_buffered_out *o = (struct io_buffered_out *)out;
        int r = flush(o), q = io_out_close(o->next);
        return r < 0 ? r : q;
}

const struct io_out_fns io_buffered_out_fns = {
        .write = io_buffered_out_write,
        .close = io_buffered_out_close
};

struct io_buffered_out
io_buffered_out_init(struct io_out *next)
{
        return IO_BUFFERED_OUT_INIT(next);
}
