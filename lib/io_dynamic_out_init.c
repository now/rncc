#include <errno.h>
#include <limits.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <def.h>
#include <io-in.h>
#include <io-out.h>
#include <io-dynamic-out.h>

static int
io_dynamic_out_resize(struct io_dynamic_out *o, size_t n)
{
        if (o->m == n)
                return 0;
        char *t = o->realloc(o->s, n);
        if (t == NULL)
                return -ENOMEM;
        return o->s = t, o->m = n, 0;
}

static int
io_dynamic_out_at_least(struct io_dynamic_out *o, size_t n)
{
        if (n < o->m)
                return 0;
        size_t m = o->m > 0 ? 2 * o->m : 16;
        return io_dynamic_out_resize(o, m > n ? m : n);
}

int
io_dynamic_out_expand(struct io_dynamic_out *o, size_t n)
{
        return n > SIZE_MAX - o->n ? -ENOMEM :
                io_dynamic_out_at_least(o, o->n + n);
}

static ssize_t
io_dynamic_out_write(struct io_out *out, const char *s, size_t n)
{
        struct io_dynamic_out *o = (struct io_dynamic_out *)out;
        int r = io_dynamic_out_expand(o, n);
        if (r < 0)
                return r;
        memcpy(o->s + o->n, s, n);
        o->n += n;
        return (ssize_t)n;
}

static int
io_dynamic_out_close(struct io_out *out)
{
        struct io_dynamic_out *o = (struct io_dynamic_out *)out;
        io_dynamic_out_resize(o, o->n);
        return 0;
}

const struct io_out_fns io_dynamic_out_fns = {
        .write = io_dynamic_out_write,
        .close = io_dynamic_out_close
};

struct io_dynamic_out
io_dynamic_out_init(void *(*realloc)(void *, size_t))
{
        return IO_DYNAMIC_OUT_INIT(realloc);
}
