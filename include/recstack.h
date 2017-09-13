// TODO We shouldn’t use realloc; user should provide it.
#define CONCAT(a, b) CONCAT1(a, b)
#define CONCAT1(a, b) a ## b

struct CONCAT(PREFIX, recstack) {
        TYPE *s;
        size_t a;
        size_t n;
        TYPE ss[32];
};

#ifndef RECSTACK_INIT
#  define RECSTACK_INIT(r) { .s = r.ss, .a = lengthof(r.ss), .n = 0 }
#endif

static int
CONCAT(PREFIX, recstack_push)(
        struct CONCAT(PREFIX, recstack) *r, TYPE *e)
{
        if (r->n == r->a) {
                if (r->s == r->ss)
                        r->s = NULL;
                size_t n = 2 * r->a;
                if (n > SIZE_MAX / 2)
                        return -ENOMEM;
                TYPE *s = realloc(r->s, n);
                if (s == NULL)
                        return -ENOMEM;
                r->s = s;
                r->a = n;
        }
        r->s[r->n++] = *e;
        return 0;
}

static void
CONCAT(PREFIX, recstack_free)(
        struct CONCAT(PREFIX, recstack) *r)
{
        if (r->s != r->ss)
                free(r->s);
}

#undef CONCAT
#undef CONCAT1
#undef PREFIX
#undef TYPE
