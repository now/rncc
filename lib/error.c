#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <def.h>
#include <io-assert.h>
#include <io-in.h>
#include <io-out.h>
#include <location.h>
#include <error.h>
#include <format.h>

struct error error_oom = {
        { { 0, 0 }, { 0, 0 } },
        ERROR_LEVEL_ERROR,
        "memory exhausted",
        true
};

int
error_init(struct error *error, void *(*malloc)(size_t),
           const struct location *l, enum error_level v, const char *message,
           ...)
{
        va_list args;
        va_start(args, message);
        int r = error_initv(error, malloc, l, v, message, args);
        va_end(args);
        return r;
}

void
error_inits(struct error *error, const struct location *l, enum error_level v,
            const char *message)
{
        *error = ERROR_INIT(*l, v, message);
}

int
error_initv(struct error *error, void *(*malloc)(size_t),
            const struct location *l, enum error_level v, const char *message,
            va_list args)
{
        *error = (struct error){
                .location = *l, .level = v, .message_is_static = false
        };
        int r;
        if ((r = formatv((char **)(uintptr_t)&error->message, malloc, message,
                         args)) < 0) {
                *error = error_oom;
                return r;
        }
        return 0;
}

int
error_str(struct io_out *out, const struct error *error)
{
        int r;
        if ((r = location_str(out, &error->location)) < 0 ||
            (r = io_write(out, ": ", 2)) < 0 ||
            (r = error_level_str(out, error->level)) < 0 ||
            (r = io_write(out, ": ", 2)) < 0)
                return r;
        return io_write_z(out, error->message);
}

void
error_free(struct error *error, void (*free)(void *))
{
        if (!error->message_is_static)
                free((char *)(uintptr_t)error->message);
}

struct errors
errors_init(struct error *s, size_t m, void *(*malloc)(size_t n))
{
        return (struct errors){ s, 0, m, malloc };
}

int
errors_add(struct errors *errors, const struct location *l, enum error_level v,
           const char *message, ...)
{
        require(errors->n < errors->m);
        va_list args;
        va_start(args, message);
        int r = errors_addv(errors, l, v, message, args);
        va_end(args);
        return r;
}

void
errors_adds(struct errors *errors, const struct location *l, enum error_level v,
            const char *message)
{
        require(errors->n < errors->m);
        error_inits(&errors->s[errors->n++], l, v, message);
}

int
errors_addv(struct errors *errors, const struct location *l, enum error_level v,
            const char *message, va_list args)
{
        require(errors->n < errors->m);
        return error_initv(&errors->s[errors->n++], errors->malloc, l, v,
                           message, args);
}

void
errors_push(struct errors *errors, struct error *error)
{
        require(errors->n < errors->m);
        errors->s[errors->n++] = *error;
}

void
errors_free(struct errors *errors, void (*free)(void *))
{
        for (size_t i = 0; i < errors->n; i++)
                error_free(&errors->s[i], free);
}

int
error_level_str(struct io_out *out, enum error_level level)
{
        static const char *const ss[] = {
                [ERROR_LEVEL_NOTE] = "note",
                [ERROR_LEVEL_ERROR] = "error"
        };
        require(0 <= level && (size_t)level < lengthof(ss));
        return io_print(out, "%s", ss[level]);
}
