#include <limits.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>

#include <def.h>
#include <io-in.h>
#include <io-out.h>
#include <location.h>

int
location_str(struct io_out *out, const struct location *l)
{
        return l->first.line == 0 ?
                0 :
                l->first.line == l->last.line ?
                l->first.column == l->last.column ?
                io_print(out, "%zu:%zu", l->first.line, l->first.column) :
                io_print(out, "%zu.%zu-%zu", l->first.line, l->first.column,
                         l->last.column) :
                io_print(out, "%zu.%zu-%zu.%zu", l->first.line, l->first.column,
                         l->last.line, l->last.column);
}
