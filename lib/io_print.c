#include <stdarg.h>
#include <stddef.h>
#include <unistd.h>

#include <def.h>
#include <io-in.h>
#include <io-out.h>

int
io_print(struct io_out *out, const char *format, ...)
{
        va_list args;
        va_start(args, format);
        int r = io_printv(out, format, args);
        va_end(args);
        return r;
}
