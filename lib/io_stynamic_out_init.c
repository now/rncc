#include <errno.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#include <def.h>
#include <io-in.h>
#include <io-out.h>
#include <io-dynamic-out.h>
#include <io-stynamic-out.h>

static ssize_t
io_stynamic_out_write(struct io_out *out, const char *s, size_t n)
{
        struct io_stynamic_out *o = (struct io_stynamic_out *)out;
        if (n > o->m - o->n) {
                o->self.fs = &io_dynamic_out_fns;
                return o->self.fs->write(out, s, n);
        }
        memcpy(o->s + o->n, s, n);
        o->n += n;
        return (ssize_t)n;
}

static int
io_stynamic_out_close(struct io_out *out)
{
        struct io_stynamic_out *o = (struct io_stynamic_out *)out;
        int r;
        if ((r = io_write(out, "", 1)) < 0 ||
            (io_stynamic_is_dynamic(o) && (r = io_out_close(out)) < 0))
                return r;
        return 0;
}

const struct io_out_fns io_stynamic_out_fns = {
        .write = io_stynamic_out_write,
        .close = io_stynamic_out_close
};

struct io_stynamic_out
io_stynamic_out_init(char *s, size_t m, void *(*realloc)(void *s, size_t n))
{
        return (struct io_stynamic_out){
                .self.fs = &io_stynamic_out_fns,
                .realloc = realloc,
                .s = s,
                .n = 0,
                .m = m,
        };
}

bool
io_stynamic_is_dynamic(struct io_stynamic_out *o)
{
        return o->self.fs == &io_dynamic_out_fns;
}
