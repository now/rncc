#include <errno.h>
#include <stdarg.h>
#include <stddef.h>
#include <string.h>

#include <def.h>
#include <io-in.h>
#include <io-out.h>
#include <io-static-out.h>

static ssize_t
io_static_out_write(struct io_out *out, const char *s, size_t n)
{
        struct io_static_out *o = (struct io_static_out *)out;
        if (n > o->m - o->n)
                return -ENOMEM;
        memcpy(o->s + o->n, s, n);
        o->n += n;
        return (ssize_t)n;
}

static int
io_static_out_close(UNUSED struct io_out *out)
{
        return 0;
}

const struct io_out_fns io_static_out_fns = {
        .write = io_static_out_write,
        .close = io_static_out_close
};

struct io_static_out
io_static_out_init(char *s, size_t m)
{
        return (struct io_static_out){
                .self.fs = &io_static_out_fns,
                .s = s,
                .n = 0,
                .m = m,
        };
}
