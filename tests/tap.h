static struct {
        size_t n;
} tap_state = { 0 };

static int
plan(size_t n)
{
        return io_print(io_stdout, "1..%zu\n", n);
}

static int
ok(bool passed, const char *description)
{
        int r = io_print(io_stdout, "%sok %zu - %s\n",
                         passed ? "" : "not ", ++tap_state.n, description);
        return r < 0 ? r : passed;
}

UNUSED static int
error(int r)
{
        io_print(io_stdout, "# error %d (%s)\n", -r, strerror(-r));
        return EXIT_FAILURE;
}

// TODO Move this to its own file.
struct string {
        const char *s;
        size_t n;
};

static int
error_string_cmp(const struct errors *errors, const struct string *s)
{
        size_t i, n;
        const char *p, *q, *end;
        struct io_static_out o = IO_STATIC_OUT_INIT(2048);
        for (i = 0, n = errors->n, p = s->s, end = p + s->n; i < n && p < end;
             i++, p = q + 1) {
                q = memchr(p, '\n', (size_t)(end - p));
                if (q == NULL)
                        q = end;
                o.n = 0;
                int r;
                if ((r = error_str(&o.self, &errors->s[i])) < 0)
                        error(r);
                else if ((size_t)(q - p) != o.n)
                        return (size_t)(q - p) < o.n ? -1 : +1;
                else if ((r = memcmp(p, o.s, o.n)) != 0)
                        return r < 0 ? -1 : +1;
        }
        return i == n && p >= end ? 0 : i == n ? -1 : +1;
}

static int
print_string(struct string *s, int w)
{
        int r;
        bool first = true;
        for (const char *p = s->s, *end = p + s->n, *q; p < end; p = q + 1) {
                q = memchr(p, '\n', (size_t)(end - p));
                if (q == NULL)
                        q = end;
                if ((!first &&
                     (r = io_print(io_stdout, "#%*s", w, "")) < 0) ||
                    (r = io_write(io_stdout, p,
                                  (size_t)(q - p))) < 0 ||
                    (r = io_print(io_stdout, "\n")) < 0)
                        return r;
                first = false;
        }
        if (s->n == 0 && (r = io_write(io_stdout, "\n", 1)) < 0)
                return r;
        return 0;
}

static int
print_errors(const struct errors *errors, int w, bool newline)
{
        for (size_t i = 0; i < errors->n; i++) {
                int r;
                if ((i > 0 && (r = io_print(io_stdout, "#%*s", w, "")) < 0) ||
                    (r = error_str(io_stdout, &errors->s[i])) < 0 ||
                    (r = io_print(io_stdout, "\n")) < 0)
                        return r;
        }
        if (newline && errors->n == 0)
                return io_print(io_stdout, "\n");
        return 0;
}
