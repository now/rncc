#include <config.h>

#include <errno.h>
#include <fcntl.h>
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
#include <io-buffered-in.h>
#include <io-fd-in.h>
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
        if ((path != NULL && (r = io_print(io_stderr, "%s:", path)) < 0) ||
            (error->location.first.line != 0 ?
             ((r = location_str(io_stderr, &error->location)) < 0 ||
              (r = io_print(io_stderr, ": ")) < 0) :
             (r = io_print(io_stderr, " ")) < 0) ||
            (r = error_level_str(io_stderr, error->level)) < 0)
                return r;
        return io_print(io_stderr, ": %s\n", error->message);
}

int
main(int argc, char **argv)
{
        int result = EXIT_SUCCESS, r = 0, in = 0, fd = STDIN_FILENO;
        if (argc > 2 && strcmp(argv[1], "--") == 0)
                in = 2;
        if (argc > 1 && strcmp(argv[1], "--version") == 0) {
                if ((r = io_print(io_stdout, "%s\n", PACKAGE_STRING)) < 0) {
                        io_print(io_stderr, "%s: %s\n", argv[0], strerror(-r));
                        result = EXIT_FAILURE;
                }
                goto exit;
        } else if (argc > 1)
                in = 1;
        if (getenv("RNCC_DEBUG"))
                rncc_debug(true);
        if (in > 0) {
                if ((fd = open(argv[in], O_RDONLY)) < 0) {
                        io_print(io_stderr, "%s: can’t read input from %s: %s\n",
                                 argv[0], argv[in], strerror(errno));
                        result = EXIT_FAILURE;
                        goto exit;
                }
        }
        struct io_dynamic_out b = io_dynamic_out_init(realloc);
        struct io_in *io_in = in > 0 ?
                &IO_BUFFERED_IN_INIT(&IO_FD_IN_INIT(fd).self).self :
                io_stdin;
        ssize_t rr;
        struct stat s;
        if (fstat(fd, &s) != -1)
                r = (sizeof(s.st_size) > sizeof(size_t) ?
                     s.st_size > (off_t)SIZE_MAX :
                     (size_t)s.st_size > SIZE_MAX) ? -ENOMEM :
                        io_dynamic_out_expand(&b, (size_t)s.st_size);
        if (r < 0 || (rr = io_feed(&b.self, io_in)) < 0) {
                io_print(io_stderr, "%s: can’t read input from %s: %s\n",
                         argv[0], in > 0 ? argv[in] : "<stdin>",
                         strerror(r < 0 ? -r : (int)-rr));
                result = EXIT_FAILURE;
                goto exit;
        }
        close(fd);
        io_out_close(&b.self);
        struct errors errors = ERRORS_INIT(20, malloc);
        r = rncc_parse(io_stdout, &errors, b.s, b.n);
        free(b.s);
        if (errors.n > 0) {
                for (size_t i = 0; i < errors.n; i++)
                        if (report_error(&errors.s[i],
                                         in > 0 ? argv[in] : NULL) < 0)
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
