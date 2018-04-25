#include <errno.h>
#include <stdarg.h>
#include <stdio.h>

#include <def.h>
#include <io-assert.h>
#include <format.h>

int
format(char **output, void *(*malloc)(size_t), const char *format, ...)
{
        va_list args;
        va_start(args, format);
        int size = formatv(output, malloc, format, args);
        va_end(args);
        return size;
}

int
formatv(char **output, void *(*malloc)(size_t), const char *format, va_list args)
{
        va_list saved;
        va_copy(saved, args);
        char buf[1];
        int r = vsnprintf(buf, sizeof(buf), format, args);
        va_end(args);
        if (r < 0) {
                va_end(saved);
                return -errno;
        }
        char *result = malloc((size_t)r + 1);
        if (result == NULL) {
                va_end(saved);
                return -errno;
        }
        require(vsnprintf(result, (size_t)r + 1, format, saved) >= 0);
        va_end(saved);
        *output = result;
        return r;
}
