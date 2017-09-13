#include <config.h>

#include <errno.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <def.h>
#include <io-assert.h>
#include <io-in.h>
#include <io-out.h>
#include <io-dynamic-out.h>
#include <io-std.h>
#include <location.h>
#include <error.h>
#include <rncc.h>

static int
report_error(const struct error *error, const char *path)
{
        int r;
        if ((path != NULL && (r = io_print(io_stderr, "%s: ", path)) < 0) ||
            (error->location.first.line != 0 &&
             ((r = location_str(io_stderr, &error->location)) < 0 ||
              (r = io_print(io_stderr, ": ")) < 0)) ||
            (r = error_level_str(io_stderr, error->level)) < 0)
                return r;
        return io_print(io_stderr, ": %s\n", error->message);
}

int
main(int argc, char **argv)
{
        int result = EXIT_SUCCESS, r = 0;
        if (argc > 1 && strcmp(argv[1], "--version") == 0) {
                if ((r = io_print(io_stdout, "%s\n", PACKAGE_STRING)) < 0) {
                        io_print(io_stderr, "%s: %s\n", argv[0], strerror(-r));
                        result = EXIT_FAILURE;
                }
                goto exit;
        }
        if (getenv("RNCC_DEBUG"))
                rncc_debug(true);
        struct io_dynamic_out b = io_dynamic_out_init(realloc);
        ssize_t rr;
        struct stat s;
        if (fstat(STDIN_FILENO, &s) != -1)
                r = (sizeof(s.st_size) > sizeof(size_t) ?
                     s.st_size > (off_t)SIZE_MAX :
                     (size_t)s.st_size > SIZE_MAX) ? -ENOMEM :
                        io_dynamic_out_expand(&b, (size_t)s.st_size);
        if (r < 0 || (rr = io_feed(&b.self, io_stdin)) < 0) {
                io_print(io_stderr, "%s: can’t read input from <stdin>: %s\n",
                         argv[0], strerror(r < 0 ? -r : (int)-rr));
                result = EXIT_FAILURE;
                goto exit;
        }
        io_out_close(&b.self);
        struct errors errors = ERRORS_INIT(20, malloc);
        r = rncc_parse(io_stdout, &errors, b.s, b.n);
        free(b.s);
        if (errors.n > 0) {
                for (size_t i = 0; i < errors.n; i++)
                        if (report_error(&errors.s[i], NULL) < 0)
                                break;
                errors_free(&errors, free);
                result = EXIT_FAILURE;
        } else if (r < 0) {
                io_print(io_stderr,
                         "%s: can’t write output to <stdout>: %s\n",
                         argv[0], strerror(-r));
                result = EXIT_FAILURE;
        }
exit:
        if (io_std_close(argv[0]) < 0)
                result = EXIT_FAILURE;
        return result;
}
