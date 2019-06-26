#include <errno.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <def.h>
#include <io-in.h>
#include <io-out.h>
#include <io-static-out.h>
#include <io-std.h>
#include <location.h>
#include <error.h>
#include <uri.h>
#include <tests/tap.h>

static const char null_string[] = { 0, 0 };

static struct test {
        const char *description;
        struct string in;
        struct uri expected;
        struct string error;
} tests[] = {
#define STRING(s) { s, sizeof(s) - 1 }
#define S(s) STRING(s)
#define _ null_string
#define E(d, in, error) \
        { d, S(in), { S(_), S(_), S(_), -1, S(_), S(_), S(_) }, S(error) }
#define U(d, in, s, u, h, o, p, q, f) \
        { d, S(in), { S(s), S(u), S(h), o, S(p), S(q), S(f) }, { NULL, 0 } }
        // URI
        U("Scheme and empty path", "a:", "a", _, _, -1, "", _, _),
        U("Scheme, empty path, and empty query",
          "a:?", "a", _, _, -1, "", "", _),
        U("Scheme, empty path, and empty fragment",
          "a:#", "a", _, _, -1, "", _, ""),
        U("Scheme, empty path, empty query, and empty fragment",
          "a:?#", "a", _, _, -1, "", "", ""),
        U("Scheme and relative path", "a:b/c", "a", _, _, -1, "b/c", _, _),
        U("Scheme, relative path, and empty query",
          "a:b/c?", "a", _, _, -1, "b/c", "", _),
        U("Scheme, relative path, and empty fragment",
          "a:b/c#", "a", _, _, -1, "b/c", _, ""),
        U("Scheme, relative path, empty query, and empty fragment",
          "a:b/c?#", "a", _, _, -1, "b/c", "", ""),
        U("Scheme and absolute path", "a:/b/c", "a", _, _, -1, "/b/c", _, _),
        U("Scheme, absolute path, and empty query",
          "a:/b/c?", "a", _, _, -1, "/b/c", "", _),
        U("Scheme, absolute path, and empty fragment",
          "a:/b/c#", "a", _, _, -1, "/b/c", _, ""),
        U("Scheme, absolute path, empty query, and empty fragment",
          "a:/b/c?#", "a", _, _, -1, "/b/c", "", ""),
        U("Scheme and relative path w/colon",
          "a:b:c", "a", _, _, -1, "b:c", _, _),
        U("Scheme and absolute path w/colon",
          "a:/b:c", "a", _, _, -1, "/b:c", _, _),
        U("Scheme, host, and empty path", "a://bc", "a", _, "bc", -1, "", _, _),
        U("Scheme, host, and root path", "a://b/", "a", _, "b", -1, "/", _, _),
        U("Scheme, host, and path", "a://b/c", "a", _, "b", -1, "/c", _, _),
        U("Scheme, host, and empty query", "a://b?", "a", _, "b", -1, "", "", _),
        U("Scheme, host, and query", "a://b?c", "a", _, "b", -1, "", "c", _),
        U("Scheme, host, and empty fragment",
          "a://b#", "a", _, "b", -1, "", _, ""),
        U("Scheme, host, and fragment", "a://b#c", "a", _, "b", -1, "", _, "c"),
        U("Scheme, host, query and empty fragment",
          "a://b?c#", "a", _, "b", -1, "", "c", ""),
        U("Scheme, host, empty query and fragment",
          "a://b?#c", "a", _, "b", -1, "", "", "c"),
        U("Scheme, host, query and fragment",
          "a://b?c#d", "a", _, "b", -1, "", "c", "d"),
        U("Scheme, userinfo, host, and empty path",
          "a://b:c@d", "a", "b:c", "d", -1, "", _, _),
        U("Scheme, host, port, and empty path",
          "a://b:1", "a", _, "b", 1, "", _, _),
        U("Scheme, host, port, and path",
          "a://b:c@d:1/e", "a", "b:c", "d", 1, "/e", _, _),
        U("Scheme, userinfo, host, and path",
          "a://b:c@d/e", "a", "b:c", "d", -1, "/e", _, _),
        U("Scheme, userinfo, host, path, and query",
          "a://b:c@d/e?f", "a", "b:c", "d", -1, "/e", "f", _),
        U("Scheme, userinfo, host, path, query, and fragment",
          "a://b:c@d/e?f#g", "a", "b:c", "d", -1, "/e", "f", "g"),
        // Relative-ref
        U("Empty path", "", _, _, _, -1, "", _, _),
        E("Illegal input in path", "-:",
          "1:2: error: unexpected content at end of input"),
        E("Illegal input in port", "a://b:1k",
          "1:8: error: unexpected content at end of input"),
        E("Broken percent-encoded character at EOI (1)", "a://b%",
          "1:6: error: incomplete ‘%’ escape sequence"),
        E("Broken percent-encoded character at EOI (2)", "a://b%1",
          "1:6: error: incomplete ‘%’ escape sequence"),
        E("Broken percent-encoded character", "a://b%y0c",
          "1:6: error: incomplete ‘%’ escape sequence"),
        E("IPvFuture with broken version number", "a://[v",
          "1:7: error: expecting one or more hexadecimal digits in IP version "
          "number\n"
          "1:7: error: expecting an ‘.’ to end IP version number\n"
          "1:7: error: empty IP address\n"
          "1.5-6: error: unterminated IP address\n"
          "1:7: note: expecting an ‘]’ here"),
        U("IPv6 literal ::1", "a://[::1]", "a", _, "[::1]", -1, "", _, _),
        E("IPv6 starting with a colon", "a://[:]",
          "1:6: error: unexpected ‘:’ at beginning of IPv6 address; treating it "
          "as “::”"),
        E("IPv6 literal with two “::” sequences", "a://[::1::2]",
          "1.9-10: error: only one “::” is allowed in an IPv6 address\n"
          "1.6-7: note: previous “::” was here"),
        E("IPv6 literal with too few groups", "a://[1:]",
          "1.6-7: error: incomplete IPv6 address\n"
          "1:8: note: expecting an additional 7 groups, starting here"),
        U("IPv6 literal with eight groups", "a://[1:2:3:4:5:6:7:8]",
          "a", _, "[1:2:3:4:5:6:7:8]", -1, "", _, _),
        E("IPv6 literal with nine groups", "a://[1:2:3:4:5:6:7:8:9]",
          "1.5-20: error: unterminated IP address\n"
          "1:21: note: expecting an ‘]’ here\n"
          "1:23: error: unexpected content at end of input"),
        E("IPv6 literal with five hexadecimal digits", "a://[12345::]",
          "1.6-9: error: hexadecimal digit sequence too long – only up to four "
          "hexadecimal digits are allowed\n"
          "1:10: note: expecting a ‘:’ here"),
        E("IPv6 literal with five hexadecimal digits", "a://[::12345]",
          "1.8-11: error: hexadecimal digit sequence too long – only up to four "
          "hexadecimal digits are allowed"),
        U("Empty port at EOI", "a://b:", "a", _, "b", -1, "", _, _),
        U("Empty port", "a://b:/c", "a", _, "b", -1, "/c", _, _),
        E("Illegal character in relative path", "[",
          "1:1: error: unexpected content at end of input"),
        E("Illegal character in path", "a:/[",
          "1:4: error: unexpected content at end of input"),
        E("IPv6 literal with broken IPv4 ending", "a://[::256.0.0.1]",
          "1.8-10: error: decimal value must be in the range 0 to 255"),
#undef STRING
#undef S
#undef _
#undef E
#undef U
};

static int
print_uri_string(struct uri_string s, const char *name, bool *c)
{
        int r;
        if (s.s == NULL)
                return 0;
        else if ((*c && (r = io_write_z(io_stdout, ", ")) < 0) ||
                 (*c = true,
                  (r = io_write_z(io_stdout, name)) < 0 ||
                  (r = io_write_z(io_stdout, ": ")) < 0))
                return r;
        return io_write(io_stdout, s.s, s.n);
}

static int
print_uri(struct uri *u)
{
        int r;
        bool c = false;
        if ((r = print_uri_string(u->scheme, "scheme", &c)) < 0 ||
            (r = print_uri_string(u->userinfo, "userinfo", &c)) < 0 ||
            (r = print_uri_string(u->host, "host", &c)) < 0 ||
            (u->port != -1 &&
             ((c && (r = io_write_z(io_stdout, ", ")) < 0) ||
              (c = true,
               (r = io_write_z(io_stdout, "port: ")) < 0 ||
               (r = io_print(io_stdout, "%ld", u->port)) < 0))) ||
            (r = print_uri_string(u->path, "path", &c)) < 0 ||
            (r = print_uri_string(u->query, "query", &c)) < 0 ||
            (r = print_uri_string(u->fragment, "fragment", &c)))
                return r;
        return io_write(io_stdout, "\n", 1);
}

int
main(UNUSED int argc, char **argv)
{
        int result = EXIT_SUCCESS, r;
        if ((r = plan(lengthof(tests))) < 0)
                goto error;
        struct errors errors = ERRORS_INIT(20, malloc);
        for (size_t i = 0; i < lengthof(tests); i++) {
                if (tests[i].expected.scheme.s == null_string)
                        tests[i].expected.scheme =
                                (struct uri_string){ NULL, 0 };
                if (tests[i].expected.userinfo.s == null_string)
                        tests[i].expected.userinfo =
                                (struct uri_string){ NULL, 0 };
                if (tests[i].expected.host.s == null_string)
                        tests[i].expected.host = (struct uri_string){ NULL, 0 };
                if (tests[i].expected.path.s == null_string)
                        tests[i].expected.path = (struct uri_string){ NULL, 0 };
                if (tests[i].expected.query.s == null_string)
                        tests[i].expected.query = (struct uri_string){ NULL, 0 };
                if (tests[i].expected.fragment.s == null_string)
                        tests[i].expected.fragment =
                                (struct uri_string){ NULL, 0 };
                struct uri uri = URI_INIT;
                errors.n = 0;
                const char *end;
                int rs = uri_parse(&uri, &errors, &end, tests[i].in.s,
                                   tests[i].in.n);
                if (end != tests[i].in.s + tests[i].in.n) {
                        errors_adds(&errors, &(struct location){
                                        {1, (size_t)(end - tests[i].in.s) + 1},
                                        {1, (size_t)(end - tests[i].in.s) + 1}
                                    }, ERROR_LEVEL_ERROR,
                                    "unexpected content at end of input");
                        if (rs == 0)
                                rs = -EILSEQ;
                }
                bool same;
                if ((r = ok(tests[i].error.s == NULL ?
                            (same = uri_cmp(&uri, &tests[i].expected) == 0) &&
                            rs >= 0 && errors.n == 0 :
                            (same = error_string_cmp(&errors,
                                                     &tests[i].error) == 0) &&
                            rs < 0,
                            tests[i].description)) < 0)
                        goto error;
                else if (!r && tests[i].error.s == NULL) {
                        if ((r = io_print(io_stdout,
                                          "# expected     %s\n"
                                          "# to parse as  ",
                                          tests[i].in.s)) < 0 ||
                            (r = print_uri(&tests[i].expected)) < 0 ||
                            (r = io_print(io_stdout, "# but got      ")) < 0 ||
                            (!same && (r = print_uri(&uri)) < 0) ||
                            (r = print_errors(&errors, 14, false)) < 0 ||
                            (rs < 0 &&
                             (r = io_print(io_stdout, "# and errno    %s\n",
                                           strerror(-rs))) < 0))
                                goto error;
                } else if (!r) {
                        if ((r = io_print(io_stdout, "# expected      ")) < 0 ||
                            (r = print_string(&tests[i].in, 15)) < 0 ||
                            (r = io_print(io_stdout, "# to result in  ")) < 0 ||
                            (r = print_string(&tests[i].error, 15)) < 0 ||
                            (!same &&
                             ((r = io_print(io_stdout,
                                            "# but got       ")) < 0 ||
                              (r = print_errors(&errors, 15, true)) < 0)) ||
                            ((uri.scheme.s != NULL ||
                              uri.userinfo.s != NULL ||
                              uri.host.s != NULL ||
                              uri.port != -1 ||
                              uri.path.s != NULL ||
                              uri.query.s != NULL ||
                              uri.fragment.s != NULL) &&
                             ((r = io_print(io_stdout, "# %s parsed as ",
                                            !same ? "and" : "but")) < 0 ||
                              (r = print_uri(&uri)) < 0)))
                                goto error;
                }
                errors_free(&errors, free);
        }
        goto done;
error:
        if (r < 0) {
                error(r);
                result = EXIT_FAILURE;
        }
done:
        if (io_std_close(argv[0]) < 0)
                result = EXIT_FAILURE;
        return result;
}
