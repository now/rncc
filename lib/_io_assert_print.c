#include <stdarg.h>
#include <stddef.h>
#include <stdlib.h>
#include <unistd.h>

#include <def.h>
#include <io-assert.h>
#include <io-in.h>
#include <io-out.h>
#include <io-std.h>

void
_io_assert_print(const char *file, unsigned int line, const char *function,
                 const char *expr, const char *message, ...)
{
        int r = io_print(io_stderr, "%s:%u: assertion failed in %s: ",
                         file, line, function);
        if (r >= 0 && expr[0] != '\0')
                r = io_print(io_stderr, "%s", expr);
        if (r >= 0 && message != NULL) {
                va_list args;
                va_start(args, message);
                r = io_printv(io_stderr, message, args);
                va_end(args);
        }
        if (r >= 0)
                io_print(io_stderr, "\n");
        abort();
}
