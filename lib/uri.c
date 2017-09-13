#include <errno.h>
#include <limits.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <def.h>
#include <io-assert.h>
#include <io-in.h>
#include <io-out.h>
#include <io-static-out.h>
#include <io-std.h>
#include <location.h>
#include <format.h>
#include <error.h>
#include <uri.h>

static inline bool
uri_is_alpha(char c)
{
        return ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z');
}

static inline bool
uri_is_digit(char c)
{
        return '0' <= c && c <= '9';
}

static inline bool
uri_is_hexdig(char c)
{
        return uri_is_digit(c) || ('a' <= c && c <= 'f') ||
                ('A' <= c && c <= 'F');
}

static inline const char *
uri_pct_encoded(struct errors *errors, const char *s, const char *q,
                const char *end)
{
        assert(q[0] == '%');
        if (q + 2 < end && uri_is_hexdig(q[1]) && uri_is_hexdig(q[2]))
                return q + 3;
        errors_adds(errors, &(struct location){
                        { 1, (size_t)(q - s) + 1 }, { 1, (size_t)(q - s) + 1 }
                }, ERROR_LEVEL_ERROR, "incomplete ‘%’ escape sequence");
        return q + 1;
}

static inline bool
uri_is_sub_delim(char c)
{
        switch (c) {
        case '!': case '$': case '&': case '\'': case '(': case ')': case '*':
        case '+': case ',': case ';': case '=': return true;
        default: return false;
        }
}

static inline bool
uri_is_unreserved(char c)
{
        return uri_is_alpha(c) || uri_is_digit(c) || c == '-' || c == '.' ||
                c == '_' || c == '~';
}

// TODO This could theoretically be its own function/file.
static int
uri_parse_ipv4(const char **r, struct errors *errors, const char *s,
               const char *end)
{
        size_t n = errors->n;
        const char *q = s;
        int v = -1, i, j;
        for (i = 0, j = 0; q < end && i < 4; q++)
                if (*q == '.' && j > 0)
                        v = -1, j = 0;
                else if ('0' <= *q && *q <= '9' && j < 3) {
                        if (v == -1) {
                                i++;
                                v = 0;
                        }
                        v = 10 * v + (*q - '0'), j++;
                        if (v > 255 && errors != NULL) {
                                errors_adds(errors, &(struct location){
                                                {1, (size_t)(q - s) - 1},
                                                {1, (size_t)(q - s) + 1}
                                            }, ERROR_LEVEL_ERROR,
                                            "decimal value must be in the range "
                                            "0 to 255");
                        }
                } else
                        break;
        if (q < end && i < 4 && errors != NULL)
                errors_adds(errors, &(struct location){
                                {1, 1}, {1, (size_t)(q - s) + 1}
                            }, ERROR_LEVEL_ERROR, "incomplete IPv4 address");
        *r = q;
        return errors->n > n ? -EILSEQ : 0;
}

// TODO This could theoretically be its own function/file.
static int
uri_parse_ipv6(const char **r, struct errors *errors, const char *s,
               const char *end)
{
        size_t n = errors->n;
        const char *q = s, *t, *cq;
        int i, ci = -1, dn = 0, hn = 0;
        if (q[0] == ':') {
                cq = q;
                if (q + 1 < end && q[1] == ':')
                        q += 2;
                else {
                        errors_adds(errors, &(struct location){ {1, 1}, {1, 1} },
                                    ERROR_LEVEL_ERROR,
                                    "unexpected ‘:’ at beginning of IPv6 "
                                    "address; treating it as “::”");
                        q++;
                }
                ci = 0;
                i = 1;
        } else
                i = 0;
        for (; q < end && i < 8; q++) {
                if (*q == ':') {
                        if (hn == 0) {
                                if (ci >= 0) {
                                        errors_adds(errors, &(struct location){
                                                        {1, (size_t)(q - s)},
                                                        {1, (size_t)(q - s) + 1}
                                                    }, ERROR_LEVEL_ERROR,
                                                    "only one “::” is allowed "
                                                    "in an IPv6 address");
                                        errors_adds(errors, &(struct location){
                                                       {1, (size_t)(cq - s) + 1},
                                                       {1, (size_t)(cq - s) + 2},
                                                    } , ERROR_LEVEL_NOTE,
                                                    "previous “::” was here");
                                } else
                                        ci = i, cq = q;
                                i++;
                        } else {
                                dn = 0, hn = 0, i++;
                                if (i == 8)
                                        break;
                        }
                } else if (*q == '.') {
                        if (dn > 0 &&
                            ((ci == -1 && i == 6) || (0 <= ci && i < 6))) {
                                size_t j = errors->n;
                                uri_parse_ipv4(&t, errors, q - dn, end);
                                for (; j < errors->n; j++)
                                        errors->s[j].location =
                                                location_translate(
                                                        errors->s[j].location,
                                                        (struct point){
                                                                1,
                                                                (size_t)(q - dn -
                                                                         s) + 1
                                                        });
                                q = t - 1;
                        } else
                                break;
                } else if (uri_is_digit(*q)) {
                        if (dn >= 0)
                                dn++;
                        hn++;
                } else if (('a' <= *q && *q <= 'f') || ('A' <= *q && *q <= 'F'))
                        dn = -1, hn++;
                else
                        break;
                if (dn > 3)
                        dn = -1;
                if (hn == 5) {
                        errors_adds(errors, &(struct location){
                                        {1, (size_t)(q - s - (hn - 1)) + 1},
                                        {1, (size_t)(q - s)}
                                    }, ERROR_LEVEL_ERROR,
                                    "hexadecimal digit sequence too long – only "
                                    "up to four hexadecimal digits are allowed");
                        if (i < 7 && ci == -1)
                                errors_adds(errors, &(struct location){
                                                {1, (size_t)(q - s) + 1},
                                                {1, (size_t)(q - s) + 1}
                                            }, ERROR_LEVEL_NOTE,
                                            "expecting a ‘:’ here");
                }
        }
        if (hn > 0)
                i++;
        if (i < 8 && ci == -1) {
                errors_adds(errors, &(struct location){
                                {1, 1}, {1, (size_t)(q - s)}
                            }, ERROR_LEVEL_ERROR,
                            "incomplete IPv6 address");
                errors_add(errors, &(struct location){
                                {1, (size_t)(q - s) + 1},
                                {1, (size_t)(q - s) + 1}
                           }, ERROR_LEVEL_NOTE,
                           "expecting an additional %d groups, starting here",
                           8 - i);
}
        *r = q;
        return errors->n > n ? -EILSEQ : 0;
}

static const char *
uri_parse_segment_(struct errors *errors, const char *s, const char *q,
                   const char *end, bool nc)
{
        while (q < end)
                if (uri_is_unreserved(*q) || uri_is_sub_delim(*q) || *q == '@')
                        q++;
                else if (*q == ':') {
                        if (nc)
                                break;
                        else
                                q++;
                } else if (*q == '%')
                        q = uri_pct_encoded(errors, s, q, end);
                else
                        break;
        return q;
}

static const char *
uri_parse_segment(struct errors *errors, const char *s, const char *q,
                  const char *end)
{
        return uri_parse_segment_(errors, s, q, end, false);
}

static const char *
uri_parse_segment_nc(struct errors *errors, const char *s, const char *q,
                     const char *end)
{
        return uri_parse_segment_(errors, s, q, end, true);
}

int
uri_parse(struct uri *uri, struct errors *errors, const char **s_end,
          const char *s, size_t n)
{
#define L &(struct location){{1, (size_t)(q - s) + 1}, {1, (size_t)(q - s) + 1}}
        const char *p = s, *q = p, *end = p + n, *r;
        bool relative = false;
        if (q < end && uri_is_alpha(*q))
                for (q++; q < end && (uri_is_alpha(*q) || uri_is_digit(*q) ||
                                      *q == '+' || *q == '-' || *q == '.'); q++)
                        ;
        if (q == end || *q != ':') {
                relative = true;
                goto relative;
        }
        uri->scheme = (struct uri_string){ p, (size_t)(q - p) };
        q++;
        if (q + 1 < end && q[0] == '/' && q[1] == '/') {
                size_t j = errors->n;
                for (q += 2, p = r = q; q < end; )
                        if (uri_is_unreserved(*q) || uri_is_sub_delim(*q))
                                q++;
                        else if (*q == ':') {
                                r = q;
                                q++;
                        } else if (*q == '%')
                                q = uri_pct_encoded(errors, s, q, end);
                        else
                                break;
                if (q < end && *q == '@') {
                        uri->userinfo = (struct uri_string){p, (size_t)(q - p)};
                        p = ++q;
                } else if (r > p) {
                        // Backtrack to the last-seen colon, the only
                        // character allowed in userinfo that’s not
                        // allowed in reg-name.
                        errors->n = j;
                        q = r;
                }
                if (q < end && *q == '[') {
                        r = q;
                        q++;
                        if (q < end && *q == 'v') {
                                if (++q == end || !uri_is_hexdig(*q))
                                        errors_adds(errors, L, ERROR_LEVEL_ERROR,
                                                    "expecting one or more "
                                                    "hexadecimal digits in IP "
                                                    "version number");
                                else
                                        q++;
                                for (; q < end && uri_is_hexdig(*q); q++)
                                        ;
                                if (q == end || *q != '.')
                                        errors_adds(errors, L, ERROR_LEVEL_ERROR,
                                                    "expecting an ‘.’ to end IP "
                                                    "version number");
                                else
                                        q++;
                                if (q == end ||
                                    !(uri_is_unreserved(*q) ||
                                      uri_is_sub_delim(*q) || *q == ':'))
                                        errors_adds(errors, L, ERROR_LEVEL_ERROR,
                                                    "empty IP address");
                                else
                                        q++;
                                for (; q < end && (uri_is_unreserved(*q) ||
                                                      uri_is_sub_delim(*q) ||
                                                      *q == ':'); q++)
                                        ;
                        } else if (q < end) {
                                const char *t;
                                j = errors->n;
                                uri_parse_ipv6(&t, errors, q, end);
                                for (; j < errors->n; j++)
                                        errors->s[j].location =
                                                location_translate(
                                                        errors->s[j].location,
                                                        (struct point){
                                                                1,
                                                                (size_t)(q - s) +
                                                                        1
                                                        });
                                q = t;
                        }
                        if (q == end || *q != ']') {
                                errors_adds(errors, &(struct location){
                                                {1, (size_t)(r - s) + 1},
                                                {1, (size_t)(q - s)}
                                            },
                                            ERROR_LEVEL_ERROR,
                                            "unterminated IP address");
                                errors_adds(errors, &(struct location){
                                                {1, (size_t)(q - s) + 1},
                                                {1, (size_t)(q - s) + 1}
                                            },
                                            ERROR_LEVEL_NOTE,
                                            "expecting an ‘]’ here");
                        } else
                                q++;
                } else {
                        while (q < end) {
                                if (uri_is_unreserved(*q) ||
                                    uri_is_sub_delim(*q))
                                        q++;
                                else if (*q == '%')
                                        q = uri_pct_encoded(errors, s, q, end);
                                else
                                        break;
                        }
                }
                uri->host = (struct uri_string){ p, (size_t)(q - p) };
                if (*q == ':') {
                        q++;
                        if (q < end && uri_is_digit(*q)) {
                                unsigned long port = (unsigned long)*q - '0';
                                for (q++; q < end && uri_is_digit(*q); q++)
                                        port = 10 * port +
                                                ((unsigned long)*q - '0');
                                uri->port = port & LONG_MAX;
                        }
                }
                p = q;
                while (q < end && *q == '/')
                        q = uri_parse_segment(errors, s, q + 1, end);
        } else if (q < end && (*q == '/' || uri_is_unreserved(*q) ||
                               *q == '%' || uri_is_sub_delim(*q) ||
                               *q == ':' || *q == '@')) {
                p = q;
                if (*q == '/')
                        q++;
        relative:
                r = (relative ?
                     uri_parse_segment_nc :
                     uri_parse_segment)(errors, s, q, end);
                if (r != q || (relative && (p != q || p == end))) {
                        q = r;
                        while (q < end && *q == '/')
                                q = uri_parse_segment(errors, s, q + 1, end);
                }
        } else
                p = q;
        uri->path = (struct uri_string){ p, (size_t)(q - p) };
        if (q < end && *q == '?') {
                q++;
                p = q;
                while (q < end) {
                        if (uri_is_unreserved(*q) ||
                            uri_is_sub_delim(*q) || *q == ':' || *q == '@')
                                q++;
                        else if (*q == '%')
                                q = uri_pct_encoded(errors, s, q, end);
                        else
                                break;
                }
                uri->query = (struct uri_string){ p, (size_t)(q - p) };
        }
        if (q < end && *q == '#') {
                q++;
                p = q;
                while (q < end) {
                        if (uri_is_unreserved(*q) ||
                            uri_is_sub_delim(*q) || *q == ':' || *q == '@')
                                q++;
                        else if (*q == '%')
                                q = uri_pct_encoded(errors, s, q, end);
                        else
                                break;
                }
                uri->fragment = (struct uri_string){ p, (size_t)(q - p) };
        }
        *s_end = q;
        return errors->n > 0 ? -EILSEQ : 0;
#undef L
}

int
uri_string_cmp(const struct uri_string *a, const struct uri_string *b)
{
        if (a->n == 0 && b->n == 0)
                return a->s == NULL ? b->s == NULL ? 0 : -1 :
                        b->s == NULL ? +1 : 0;
        else if (a->n == b->n)
                return memcmp(a->s, b->s, b->n);
        else {
                int c = memcmp(a->s, b->s, a->n < b->n ? a->n : b->n);
                return c != 0 ? c : a->n < b->n ? -1 : +1;
        }
}

// TODO Scheme should be compared case-insensitively.
// TODO Host should be compared case-insensitively.
int
uri_cmp(const struct uri *a, const struct uri *b)
{
        int r;
        if ((r = uri_string_cmp(&a->scheme, &b->scheme)) != 0 ||
            (r = uri_string_cmp(&a->userinfo, &b->userinfo)) != 0 ||
            (r = uri_string_cmp(&a->host, &b->host)) != 0 ||
            (r = a->port == b->port ? 0 : a < b ? -1 : +1) != 0 ||
            (r = uri_string_cmp(&a->path, &b->path)) != 0 ||
            (r = uri_string_cmp(&a->query, &b->query)) != 0 ||
            (r = uri_string_cmp(&a->fragment, &b->fragment)) != 0)
                return r;
        return 0;
}
