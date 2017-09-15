// TODO Add error recovery rules to be able to report as many errors
// at once as possible.

%code requires {
#include <config.h>

#include <errno.h>
#include <limits.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <def.h>
#include <io-assert.h>
#include <io-in.h>
#include <io-out.h>
#include <io-dynamic-out.h>
#include <io-std.h>
#include <io-stynamic-out.h>
#include <location.h>
#include <error.h>
#include <rncc.h>
#include <uri.h>

struct element;
struct parser;

#define YYLTYPE struct location

#define YYLLOC_DEFAULT(C, R, N) do { \
        if (N) { \
                (C).first = YYRHSLOC(R, 1).first; \
                (C).last = YYRHSLOC(R, N).last; \
        } else { \
                (C).first.line = (C).last.line = YYRHSLOC(R, 0).last.line; \
                (C).first.column = (C).last.column = YYRHSLOC(R, 0).last.column;\
        } \
 } while (0)


typedef unsigned int uc;

#define UC_MAX 0x10ffff
#define UC_BYTES_MAX 4
#define UC_C(c) (c ## U)
#define UC_PRIX "X"
#define UC_PRIU "U+%04" UC_PRIX

// The dfa table and decode function is © 2008–2010 Björn Höhrmann
// <bjoern@hoehrmann.de>.  See http://bjoern.hoehrmann.de/utf-8/decoder/dfa/
// for details.

enum {
        ACCEPT = 0,
        REJECT = 12
};

static const unsigned char dfa[] = {
        // The first part of the table maps bytes to character classes to
        // reduce the size of the transition table and create bitmasks.
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,  9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,
        7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,  7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
        8,8,2,2,2,2,2,2,2,2,2,2,2,2,2,2,  2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,
       10,3,3,3,3,3,3,3,3,3,3,3,3,4,3,3, 11,6,6,6,5,8,8,8,8,8,8,8,8,8,8,8,

        // The second part is a transition table that maps a combination
        // of a state of the automaton and a character class to a state.
        0,12,24,36,60,96,84,12,12,12,48,72, 12,12,12,12,12,12,12,12,12,12,12,12,
       12, 0,12,12,12,12,12, 0,12, 0,12,12, 12,24,12,12,12,12,12,24,12,24,12,12,
       12,12,12,12,12,12,12,24,12,12,12,12, 12,24,12,12,12,12,12,12,12,24,12,12,
       12,12,12,12,12,12,12,36,12,36,12,12, 12,36,12,12,12,12,12,36,12,36,12,12,
       12,36,12,12,12,12,12,12,12,12,12,12,
};

static inline unsigned char
decode(unsigned char *restrict state, uc *restrict c, unsigned char b)
{
        unsigned char type = dfa[b];
        *c = *state != ACCEPT ? (*c << 6) | (b & 0x3f) : (0xff >> type) & b;
        return *state = dfa[256 + *state + type];
}

#define REPLACEMENT_CHARACTER UC_C(0xfffd)
static const char u_replacement_character_s[] = { '\xef', '\xbf', '\xbd' };

static uc
u_decode(const char **q, const char *u, const char *end)
{
        require(u < end);
        uc c;
        unsigned char state = ACCEPT;
        for (const char *p = u; p < end; p++)
                switch (decode(&state, &c, (unsigned char)*p)) {
                case ACCEPT:
                        *q = p + 1;
                        return c;
                case REJECT:
                        goto fail;
                }
fail:
        *q = u + 1;
        return REPLACEMENT_CHARACTER;
}

static size_t
uc_encode(char *u, size_t n, uc c)
{
        if (c < 0x80) {
                if (n > 0)
                        u[0] = (char)c;
                return 1;
        }
        size_t m;
        if (c < 0x800)
                m = 2;
        else if (c < 0x10000) {
                if (0xd800 <= c && c < 0xe000)
                        return 0;
                m = 3;
        } else if (c <= UC_MAX)
                m = 4;
        else
                return 0;
        if (n >= m)
                switch (m) {
                case 4: u[3] = (char)(0x80 | (c & 0x3f)); c >>= 6; c |= 0x10000;
                case 3: u[2] = (char)(0x80 | (c & 0x3f)); c >>= 6; c |= 0x800;
                case 2: u[1] = (char)(0x80 | (c & 0x3f)); c >>= 6; c |= 0xc0;
                        u[0] = (char)c;
                }
        return m;
}

#define YY_LOCATION_PRINT(File, Loc) print_location(parser, File, &(Loc))
}

%union {
        struct string {
                const char *s;
                size_t n;
                bool shared;
        } string;
        struct literals {
                struct literal {
                        struct literal *next;
                        struct string string;
                        struct location location;
                } *first;
                struct literal *last;
        } literals;
        struct string keyword;
        struct name {
                struct string uri;
                struct string local;
        } name;
        struct q_name {
                struct string prefix;
                struct string local;
                struct location prefix_location;
        } q_name;
        struct attribute {
                struct attribute *next;
                struct location location;
                struct name name;
                struct string value;
        } *attribute;
        struct attributes {
                struct attribute *first;
                struct attribute *last;
        } attributes;
        struct content {
                struct child {
                        struct child *next;
                        enum child_type {
                                CHILD_TYPE_ELEMENT,
                                CHILD_TYPE_TEXT
                        } type;
                } *first;
                struct child *last;
        } content;
        struct element {
                struct child self;
                struct name name;
                struct attributes attributes;
                struct content children;
        } *element;
        struct elements {
                struct element *first;
                struct element *last;
        } elements;
        struct text {
                struct child self;
                struct string string;
        } *text;
        struct xml {
                struct attributes attributes;
                struct content content;
        } xml;
}

%code {
struct parser {
        const char *p;
        const char *end;
        struct point l;
        struct environment {
                struct namespace_mapping {
                        struct namespace_mapping *next;
                        struct location location;
                        struct string prefix;
                        struct string uri;
                        bool used;
                } *ds;
                struct namespace_mapping *ns;
                struct default_namespace {
                        struct location location;
                        struct string uri;
                } d;
        } environment;
        struct element *top_level;
        struct errors *errors;
        void *(*realloc)(void *, size_t);
        void (*free)(void *);
};

static unsigned int
print_location(struct parser *parser, FILE *out, const YYLTYPE *location)
{
        struct io_stynamic_out o = IO_STYNAMIC_OUT_INIT(256, parser->realloc);
        if (location_str(&o.self, location) >= 0)
                fwrite(o.s, 1, o.n, out);
        if (io_stynamic_is_dynamic(&o))
                parser->free(o.s);
        return 0;
}

static void
string_print(struct string s, FILE *f)
{
        fwrite(s.s, 1, s.n, f);
}

static void
literals_print(struct literals ls, FILE *f)
{
        string_print(ls.first->string, f);
        list_for_each(struct literal, p, ls.first->next) {
                fputc('~', f);
                string_print(p->string, f);
        }
}

static void
name_print(struct name n, FILE *f)
{
        fprintf(f, "{");
        string_print(n.uri, f);
        fprintf(f, "}");
        string_print(n.local, f);
}

static void
q_name_print(struct q_name q, FILE *f)
{
        string_print(q.prefix, f);
        fprintf(f, ":");
        string_print(q.local, f);
}

static void
attribute_print(struct attribute *a, FILE *f)
{
        name_print(a->name, f);
        fprintf(f, "=\"");
        string_print(a->value, f);
        fprintf(f, "\"");
}

static void
attributes_print(struct attributes as, FILE *f)
{
        if (as.first != NULL) {
                attribute_print(as.first, f);
                if (as.last != NULL && as.last != as.first) {
                        fprintf(f, "…");
                        attribute_print(as.last, f);
                }
        }
}

static void element_print(struct element *e, FILE *f);

static void
text_print(struct text *t, FILE *f)
{
        string_print(t->string, f);
}

static void
child_print(struct child *c, FILE *f)
{
        switch (c->type) {
        case CHILD_TYPE_ELEMENT:
                element_print((struct element *)c, f);
                break;
        case CHILD_TYPE_TEXT:
                text_print((struct text *)c, f);
                break;
        default:
                abort();
        }
}

static void
content_print(struct content cs, FILE *f)
{
        if (cs.first != NULL) {
                child_print(cs.first, f);
                if (cs.last != NULL && cs.last != cs.first) {
                        fprintf(f, "…");
                        child_print(cs.last, f);
                }
        }
}

static void
element_print(struct element *e, FILE *f)
{
        fprintf(f, "<");
        name_print(e->name, f);
        if (e->attributes.first != NULL) {
                fprintf(f, " ");
                attributes_print(e->attributes, f);
        }
        if (e->children.first == NULL)
                fprintf(f, "/");
        fprintf(f, ">");
        content_print(e->children, f);
        if (e->children.first != NULL) {
                fprintf(f, "</");
                name_print(e->name, f);
                fprintf(f, ">");
        }
}

static void
elements_print(struct elements es, FILE *f)
{
        if (es.first != NULL) {
                element_print(es.first, f);
                if (es.last != NULL && es.last != es.first) {
                        fprintf(f, "…");
                        element_print(es.last, f);
                }
        }
}

static void
xml_print(struct xml xml, FILE *f)
{
        fprintf(f, "((");
        attributes_print(xml.attributes, f);
        fprintf(f, "), (");
        content_print(xml.content, f);
        fprintf(f, "))");
}
}

%printer { literals_print($$, yyoutput); } <literals>
%printer { string_print($$, yyoutput); } <string>
%printer { string_print($$, yyoutput); } <keyword>
%printer { name_print($$, yyoutput); } <name>
%printer { q_name_print($$, yyoutput); } <q_name>
%printer { attribute_print($$, yyoutput); } <attribute>
%printer { attributes_print($$, yyoutput); } <attributes>
%printer { content_print($$, yyoutput); } <content>
%printer { element_print($$, yyoutput); } <element>
%printer { elements_print($$, yyoutput); } <elements>
%printer { xml_print($$, yyoutput); } <xml>

%destructor { literals_free(parser, $$); } <literals>
%destructor { string_free(parser, $$); } <string>
%destructor { name_free(parser, $$); } <name>
%destructor { string_free(parser, $$.prefix);
              string_free(parser, $$.local); } <q_name>
%destructor { attribute_free(parser, $$); } <attribute>
%destructor { attributes_free(parser, $$); } <attributes>
%destructor { content_free(parser, $$); } <content>
%destructor { element_free(parser, $$); } <element>
%destructor { elements_free(parser, $$); } <elements>
%destructor { attributes_free(parser, $$.attributes);
              content_free(parser, $$.content); } <xml>

%code {
static bool
parser_is_oom(const struct parser *parser)
{
        return parser->errors->n > 0 &&
                parser->errors->s[parser->errors->n - 1].message ==
                error_oom.message;
}

static bool
parser_has_enough_errors(const struct parser *parser)
{
        return parser->errors->n == parser->errors->m ||
                parser_is_oom(parser);
}

static void
parser_oom(struct parser *parser, const YYLTYPE *location)
{
        if (parser_is_oom(parser))
                return;
        error_oom.location = *location;
        if (parser->errors->n < parser->errors->m)
                errors_push(parser->errors, &error_oom);
        else {
                require(parser->errors->m > 0);
                parser->errors->s[parser->errors->m - 1] = error_oom;
        }
}

static bool PRINTF(4, 0)
_parser_errorv(struct parser *parser, const YYLTYPE *location,
               enum error_level level, const char *message, va_list args)
{
        if (parser_has_enough_errors(parser))
                return false;
        return errors_addv(parser->errors, location, level, message, args) >= 0;
}

static bool PRINTF(3, 0)
parser_errorv(struct parser *parser, const YYLTYPE *location,
              const char *message, va_list args)
{
        return _parser_errorv(parser, location, ERROR_LEVEL_ERROR, message,
                                args);
}

static bool PRINTF(3, 4)
parser_error(struct parser *parser, const YYLTYPE *location,
             const char *message, ...)
{
        va_list args;
        va_start(args, message);
        bool r = parser_errorv(parser, location, message, args);
        va_end(args);
        return r;
}

static bool
parser_error_s(struct parser *parser, const YYLTYPE *location,
               const char *message)
{
        if (parser_has_enough_errors(parser))
                return false;
        errors_adds(parser->errors, location, ERROR_LEVEL_ERROR, message);
        return true;
}

static bool PRINTF(3, 4)
parser_note(struct parser *parser, const YYLTYPE *location, const char *message,
            ...)
{
        va_list args;
        va_start(args, message);
        bool r = _parser_errorv(parser, location, ERROR_LEVEL_NOTE, message,
                                args);
        va_end(args);
        return r;
}

#undef STRING
#define STRING(s) (struct string){ s, sizeof(s) - 1, true }

static const char _inherit[8] = "inherit";
static const struct string inherit = STRING(_inherit);

static const struct string uri_rng =
        STRING("http://relaxng.org/ns/structure/1.0");

static const struct string prefix_xml = STRING("xml");
static const struct string uri_xml =
        STRING("http://www.w3.org/XML/1998/namespace");

static const struct string prefix_xmlns = STRING("xmlns");
static const struct string uri_xmlns =
        STRING("http://www.w3.org/2000/xmlns");

static const struct string prefix_xsd = STRING("xsd");
static const struct string uri_xsd =
        STRING("http://www.w3.org/2001/XMLSchema-datatypes");

#define NAME(uri, local) (struct name){ uri, local }
#define LNAME(local) NAME(STRING(""), STRING(local))

static const struct name name_documentation =
        NAME(STRING("http://relaxng.org/ns/compatibility/annotations/1.0"),
             STRING("documentation"));

static bool
string_is_inherit(struct string s)
{
        return memcmp(&s, &inherit, sizeof(s)) == 0;
}

static int
string_cmp(struct string a, struct string b)
{
        if (a.n == b.n)
                return memcmp(a.s, b.s, b.n);
        else {
                int c = memcmp(a.s, b.s, a.n < b.n ? a.n : b.n);
                return c != 0 ? c : a.n < b.n ? -1 : +1;
        }
}

static void
string_free(const struct parser *parser, struct string s)
{
        if (!s.shared)
                parser->free((char *)(uintptr_t)s.s);
}

static struct literals
literals_concat(struct literals left, struct literals right)
{
        left.last->next = right.first;
        return (struct literals){ left.first, right.last };
}

// TODO Should we be freeing strings inside ls?
static struct string
literals_to_string(const struct parser *parser, struct literals ls)
{
        if (ls.first == ls.last)
                return ls.first->string;
        struct io_dynamic_out o = IO_DYNAMIC_OUT_INIT(parser->realloc);
        int r = 0;
        list_for_each(struct literal, p, ls.first)
                if ((r = io_write(&o.self, p->string.s, p->string.n)) < 0)
                        break;
        io_out_close(&o.self);
        return r < 0 ?
                (struct string){ NULL, 0, true } :
                o.s == NULL ?
                STRING("") :
                (struct string){ o.s, o.n, false };
}

static void
literals_free(const struct parser *parser, struct literals ls)
{
        list_for_each_safe(struct literal, p, n, ls.first)
                string_free(parser, p->string);
}

static struct xml
empty(void)
{
        return (struct xml){ { NULL, NULL }, { NULL, NULL } };
}

static struct name
name(struct string uri, struct string local)
{
        return (struct name){ uri, local };
}

static int
name_cmp(struct name a, struct name b)
{
        int c = string_cmp(a.uri, b.uri);
        return c != 0 ? c : string_cmp(a.local, b.local);
}

static void
name_free(const struct parser *parser, struct name name)
{
        string_free(parser, name.uri);
        string_free(parser, name.local);
}

static struct attribute *
foreign_attribute(const struct parser *parser, YYLTYPE location,
                  struct name name, struct string value)
{
        if (value.s == NULL)
                return NULL;
        struct attribute *p = parser->realloc(NULL, sizeof(*p));
        if (p == NULL)
                return NULL;
        *p = (struct attribute){ NULL, location, name, value };
        return p;
}

static struct attribute *
attribute(const struct parser *parser, struct name name, struct string value)
{
        return foreign_attribute(parser, LOCATION_NULL, name, value);
}

static struct attributes
attribute_to_attributes(struct attribute *attribute)
{
        assert(attribute == NULL || attribute->next == NULL);
        return (struct attributes){ attribute, attribute };
}

static void
attribute_free(const struct parser *parser, struct attribute *attribute)
{
        if (attribute == NULL)
                return;
        name_free(parser, attribute->name);
        string_free(parser, attribute->value);
        parser->free(attribute);
}

static struct attributes
attributes_concat(struct attributes left, struct attributes right)
{
        if (right.first == NULL) {
                assert(right.last == NULL);
                return left;
        } else if (left.first == NULL) {
                assert(left.last == NULL);
                left.first = right.first;
        } else
                left.last->next = right.first;
        return (struct attributes){ left.first, right.last };
}

static struct attributes
attributes_cons(struct attribute *attribute, struct attributes attributes)
{
        return attributes_concat(attribute_to_attributes(attribute), attributes);
}

static struct attributes
attributes_append(struct attributes attributes, struct attribute *attribute)
{
        return attributes_concat(attributes, attribute_to_attributes(attribute));
}

static bool
attributes_check_for_duplicates(struct attributes attributes,
                                struct parser *parser)
{
        bool r = false;
        list_for_each(struct attribute, a, attributes.first)
                list_for_each(struct attribute, b, a->next)
                        if (name_cmp(a->name, b->name) == 0) {
                                r = true;
                                require(b->name.uri.n <= INT_MAX);
                                require(b->name.local.n <= INT_MAX);
                                // TODO Consider changing this to
                                // “attribute has already been set”.
                                parser_error(parser, &b->location,
                                             "attribute with namespace URI "
                                             "“%.*s” and local name “%.*s” has "
                                             "already been set",
                                             (int)b->name.uri.n, b->name.uri.s,
                                             (int)b->name.local.n,
                                             b->name.local.s);
                                if (!parser_note(parser, &a->location,
                                                 "it was previously set here"))
                                        break;
                        }
        return r;
}

static struct xml
attributes_to_xml(struct attributes attributes)
{
        return (struct xml){ attributes, { NULL, NULL } };
}

static void
attributes_free(const struct parser *parser, struct attributes attributes)
{
        list_for_each_safe(struct attribute, p, n, attributes.first)
                attribute_free(parser, p);
}

static struct content
content_concat(struct content left, struct content right)
{
        if (right.first == NULL) {
                assert(right.last == NULL);
                return left;
        } else if (left.first == NULL) {
                assert(left.last == NULL);
                left.first = right.first;
        } else
                left.last->next = right.first;
        return (struct content){ left.first, right.last };
}

static void element_free(const struct parser *parser, struct element *element);
static void text_free(const struct parser *parser, struct text *text);

static struct content
content_empty(void)
{
        return (struct content){ NULL, NULL };
}

static void
content_free(const struct parser *parser, struct content content)
{
        list_for_each_safe(struct child, p, n, content.first)
                if (p->type == CHILD_TYPE_ELEMENT)
                        element_free(parser, (struct element *)p);
                else
                        text_free(parser, (struct text *)p);
}

static struct element *
element(const struct parser *parser, struct name name, struct xml xml)
{
        struct element *p = parser->realloc(NULL, sizeof(*p));
        if (p == NULL)
                return NULL;
        *p = (struct element){
                { NULL, CHILD_TYPE_ELEMENT }, name, xml.attributes, xml.content
        };
        return p;
}

static struct element *
rng_element(const struct parser *parser, struct string x, struct xml y)
{
        return element(parser, NAME(uri_rng, x), y);
}

static struct elements
element_to_elements(struct element *element)
{
        return (struct elements){ element, element };
}

static struct xml
element_to_xml(struct element *element)
{
        if (element == NULL)
                return empty();
        assert(element->self.next == NULL);
        return (struct xml){
                { NULL, NULL },
                { &element->self, &element->self }
        };
}

static void
element_free(const struct parser *parser, struct element *element)
{
        if (element == NULL)
                return;
        name_free(parser, element->name);
        attributes_free(parser, element->attributes);
        content_free(parser, element->children);
        parser->free(element);
}

static struct elements
elements_empty(void)
{
        return element_to_elements(NULL);
}

static struct elements
elements_concat(struct elements left, struct elements right)
{
        if (right.first == NULL) {
                assert(right.last == NULL);
                return left;
        } else if (left.first == NULL) {
                assert(left.last == NULL);
                left.first = right.first;
        } else
                left.last->self.next = &right.first->self;
        return (struct elements){ left.first, right.last };
}

static struct elements
elements_cons(struct element *element, struct elements elements)
{
        return elements_concat(element_to_elements(element), elements);
}

static struct elements
elements_append(struct elements elements, struct element *element)
{
        return elements_concat(elements, element_to_elements(element));
}

static struct content
elements_to_content(struct elements elements)
{
        return (struct content){ &elements.first->self, &elements.last->self };
}

static struct xml
elements_to_xml(struct elements elements)
{
        return (struct xml){
                { NULL, NULL },
                elements_to_content(elements)
        };
}

static void
elements_free(const struct parser *parser, struct elements elements)
{
        content_free(parser, elements_to_content(elements));
}

static struct content
text(const struct parser *parser, struct string s)
{
        if (s.s == NULL)
                return (struct content){ NULL, NULL };
        struct text *p = parser->realloc(NULL, sizeof(*p));
        if (p == NULL)
                return (struct content){ NULL, NULL };
        *p = (struct text){ { NULL, CHILD_TYPE_TEXT }, s };
        return (struct content){ &p->self, &p->self };
}

static void
text_free(const struct parser *parser, struct text *text)
{
        if (text == NULL)
                return;
        string_free(parser, text->string);
        parser->free(text);
}

static struct xml
attributes_and_elements_to_xml(struct attributes attributes,
                               struct elements elements)
{
        return (struct xml){ attributes, elements_to_content(elements) };
}

static struct xml
concat(struct xml left, struct xml right)
{
        if (left.attributes.first == NULL) {
                assert(left.attributes.last == NULL);
                left.attributes.first = right.attributes.first;
        } else
                left.attributes.last->next = right.attributes.first;
        if (left.content.first == NULL) {
                assert(left.content.last == NULL);
                left.content.first = right.content.first;
        } else
                left.content.last->next = right.content.first;
        return (struct xml){
                { left.attributes.first, right.attributes.last },
                { left.content.first, right.content.first }
        };
}

static bool
_lookup_prefix(struct namespace_mapping **mapping, struct parser *parser,
               struct namespace_mapping *mappings, const YYLTYPE *location,
               struct string prefix)
{
        list_for_each(struct namespace_mapping, p, mappings)
                if (string_cmp(p->prefix, prefix) == 0)
                        return *mapping = p, true;
        require(prefix.n <= INT_MAX);
        // TODO Consider changing to “undeclared prefix”.
        parser_error(parser, location, "undeclared prefix “%.*s”",
                     (int)prefix.n, prefix.s);
        return false;
}

static bool
use_prefix(struct string *uri, struct parser *parser,
           const YYLTYPE *location, struct string prefix)
{
        struct namespace_mapping *m;
        return _lookup_prefix(&m, parser, parser->environment.ns, location,
                              prefix) ? m->used = true, *uri = m->uri, true :
                false;
}

static bool
lookup_prefix(struct string *uri, struct parser *parser,
              const YYLTYPE *location, struct string prefix)
{
        struct namespace_mapping *m;
        return _lookup_prefix(&m, parser, parser->environment.ns, location,
                              prefix) ? *uri = m->uri, true : false;
}

static struct string
lookup_default(const struct environment *environment)
{
        return environment->d.uri;
}

static bool
lookup_datatype_prefix(struct string *uri, struct parser *parser,
                       const YYLTYPE *location, struct string prefix)
{
        struct namespace_mapping *m;
        return _lookup_prefix(&m, parser, parser->environment.ds, location,
                              prefix) ? *uri = m->uri, true : false;
}

static bool
_bind_prefix(struct parser *parser, const YYLTYPE *location,
             struct string prefix, struct string uri,
             struct namespace_mapping **ns)
{
        list_for_each(struct namespace_mapping, p, *ns)
                if (string_cmp(p->prefix, prefix) == 0) {
                        if (p->location.first.line == 0) {
                                parser_error(parser, location, "prefix “%.*s” "
                                             "has already been bound to “%.*s” "
                                             "in the initial environment",
                                             (int)prefix.n, prefix.s,
                                             (int)p->uri.n, p->uri.s);
                        } else {
                                // TODO Consider simplifying error messages.
                                // “prefix has already been bound”
                                // “previous binding was made here”
                                parser_error(parser, location, "prefix “%.*s” "
                                             "has already been bound to “%.*s”",
                                             (int)prefix.n, prefix.s,
                                             (int)p->uri.n, p->uri.s);
                                parser_note(parser, &p->location,
                                            "previous binding of “%.*s” was "
                                            "made here",
                                            (int)prefix.n, prefix.s);
                        }
                        return false;
                }
        struct namespace_mapping *p = parser->realloc(NULL, sizeof(*p));
        if (p == NULL) {
                parser_oom(parser, location);
                return false;
        }
        *p = (struct namespace_mapping){ *ns, *location, prefix, uri, false };
        *ns = p;
        return true;
}

static bool
bind_prefix(struct parser *parser, YYLTYPE location, struct string prefix,
            const YYLTYPE *prefix_location, struct string uri,
            const YYLTYPE *uri_location)
{
        if (string_cmp(prefix, prefix_xml) == 0 &&
            string_cmp(uri, uri_xml) != 0) {
                parser_error_s(parser, uri_location, "prefix “xml” can only be "
                               "bound to namespace URI "
                               "“http://www.w3.org/XML/1998/namespace”");
                return false;
        }
        if (string_cmp(uri, uri_xml) == 0 &&
            string_cmp(prefix, prefix_xml) != 0) {
                parser_error_s(parser, prefix_location, "only prefix “xml” can "
                               "be bound to namespace URI "
                               "“http://www.w3.org/XML/1998/namespace”");
                return false;
        }
        return _bind_prefix(parser, &location, prefix, uri,
                            &parser->environment.ns);
}

static bool
bind_default(struct parser *parser, YYLTYPE location, struct string uri,
             const YYLTYPE *uri_location)
{
        if (string_cmp(uri, uri_xml) == 0) {
                parser_error_s(parser, uri_location,
                               "default namespace can’t be set to "
                               "“http://www.w3.org/XML/1998/namespace”");
                return false;
        }
        if (string_is_inherit(uri) ||
            !string_is_inherit(parser->environment.d.uri)) {
                // TODO Make these errors static?
                parser_error(parser, &location,
                             "default namespace has already been set to “%.*s”",
                             (int)parser->environment.d.uri.n,
                             parser->environment.d.uri.s);
                parser_note(parser, &parser->environment.d.location,
                            "it was set here");
                return false;
        }
        parser->environment.d = (struct default_namespace){ location, uri };
        return true;
}

static void
adjust_uri_errors(struct parser *parser, size_t n, struct literals ls)
{
        for (; n < parser->errors->n; n++) {
                // We can’t quite asume that
                // parser->errors->s[n..parser->errors->n) is sorted,
                // so restart the search for each iteration.
                struct literal *l = ls.first;
                size_t m = 0;
                while (m + l->string.n <
                       parser->errors->s[n].location.first.column) {
                        m += l->string.n;
                        l = l->next;
                        assert(l != NULL);
                }
                // We now know that this error at least starts here.
                parser->errors->s[n].location.first = (struct point){
                        l->location.first.line,
                        l->location.first.column +
                        (parser->errors->s[n].location.first.column - (m + 1))
                };
                while (m + l->string.n <
                       parser->errors->s[n].location.last.column) {
                        m += l->string.n;
                        l = l->next;
                        assert(l != NULL);
                }
                parser->errors->s[n].location.last = (struct point){
                        l->location.first.line,
                        l->location.first.column +
                        (parser->errors->s[n].location.last.column - (m + 1))
                };
        }
}

static bool
bind_datatype_prefix(struct parser *parser, YYLTYPE location,
                     struct string prefix, struct literals ls,
                     const YYLTYPE *ls_location)
{
        struct string uri = literals_to_string(parser, ls);
        if (uri.s == NULL) {
                parser_oom(parser, ls_location);
                return false;
        }
        // TODO We need to free stuff in namespace mappings later on.
        uri.shared = true;
        if (string_cmp(prefix, prefix_xsd) == 0 &&
            string_cmp(uri, uri_xsd) != 0) {
                parser_error_s(parser, ls_location, "prefix “xsd” can only be "
                               "bound to namespace URI "
                               "“http://www.w3.org/2001/XMLSchema-datatypes”");
                return false;
        }
        struct uri u = URI_INIT;
        size_t n = parser->errors->n;
        const char *end;
        int r = uri_parse(&u, parser->errors, &end, uri.s, uri.n);
        if (end != uri.s + uri.n) {
                parser_error_s(parser, &(struct location){
                                {1, (size_t)(end - uri.s) + 1},
                                {1, (size_t)(end - uri.s) + 1}
                               }, "invalid URI content starting here");
                if (r == 0)
                        r = -EILSEQ;
        }
        if (u.fragment.n != 0) {
                parser_error_s(parser, &(struct location){
                                {1, (size_t)(u.fragment.s - uri.s)},
                                {1, (size_t)(u.fragment.s + u.fragment.n -
                                             uri.s)}
                               },
                               "datatypes URI mustn’t include a fragment "
                               "identifier");
                if (r == 0)
                        r = -EILSEQ;
        }
        adjust_uri_errors(parser, n, ls);
        if (u.scheme.n == 0) {
                parser_error_s(parser, ls_location,
                               "datatypes URI mustn’t be relative");
                if (r == 0)
                        r = -EILSEQ;
        }
        if (r < 0)
                return false;
        return _bind_prefix(parser, &location, prefix, uri,
                            &parser->environment.ds);
}

static struct string
map_schema_ref(UNUSED struct environment *environment, struct string uri)
{
        return uri;
}

static bool
make_ns_attribute(struct attributes *attributes, const struct parser *parser,
                  struct string uri)
{
        if (string_is_inherit(uri))
                return *attributes = empty().attributes, true;
        *attributes = attribute_to_attributes(attribute(parser,
                                                        LNAME("ns"), uri));
        return attributes->first != NULL;
}

static struct element *
apply_annotations(struct xml xml, struct element *element)
{
        element->attributes = attributes_concat(element->attributes,
                                                xml.attributes);
        element->children = content_concat(xml.content, element->children);
        return element;
}

static struct elements
apply_annotations_group(const struct parser *parser, struct xml xml,
                        struct elements elements)
{
        if (xml.attributes.first == NULL && xml.content.first == NULL) {
                assert(xml.attributes.last == NULL);
                assert(xml.content.last == NULL);
                return elements;
        }
        struct element *e = rng_element(parser, STRING("group"),
                                        elements_to_xml(elements));
        if (e == NULL)
                return elements_empty();
        return element_to_elements(apply_annotations(xml, e));
}

static struct elements
apply_annotations_choice(const struct parser *parser, struct xml xml,
                         struct elements elements)
{
        if (xml.attributes.first == NULL && xml.content.first == NULL) {
                assert(xml.attributes.last == NULL);
                assert(xml.content.last == NULL);
                return elements;
        }
        struct element *e = rng_element(parser, STRING("choice"),
                                        elements_to_xml(elements));
        if (e == NULL)
                return elements_empty();
        return element_to_elements(apply_annotations(xml, e));
}

static struct attributes
datatype_attributes(const struct parser *parser, struct string library,
                    struct string type)
{
        struct attribute *l = attribute(parser, LNAME("datatypeLibrary"),
                                        library);
        struct attribute *t = NULL;
        if (l != NULL) {
                t = attribute(parser, LNAME("type"), type);
                l->next = t;
                if (t == NULL) {
                        parser->free(l);
                        l = NULL;
                }
        }
        return (struct attributes){ l, t };
}

static struct element *
rng_element_with_attribute(const struct parser *parser,
                           struct string element_name,
                           struct string attribute_name, struct string value,
                           struct attributes attributes,
                           struct content content)
{
        struct attribute *a = attribute(parser, NAME(STRING(""), attribute_name),
                                        value);
        if (a == NULL)
                return NULL;
        struct element *e = rng_element(parser, element_name, (struct xml) {
                                                attributes_cons(a, attributes),
                                                content });
        if (e == NULL)
                parser->free(a);
        return e;
}

static struct element *
rng_element_with_element(const struct parser *parser, struct string parent_name,
                         struct attributes attributes,
                         struct elements parent_elements,
                         struct string child_name,
                         struct elements child_elements)
{
        struct element *c = rng_element(parser, child_name,
                                        elements_to_xml(child_elements));
        if (c == NULL)
                return NULL;
        struct element *p = rng_element(parser, parent_name,
                                        attributes_and_elements_to_xml(
                                                attributes,
                                                elements_append(parent_elements,
                                                                c)));
        if (p == NULL)
                parser->free(c);
        return p;
}

static struct element *
rng_element_with_text(const struct parser *parser, struct string name,
                      struct attributes attributes, struct string string)
{
        struct content c = text(parser, string);
        if (c.first == NULL)
                return NULL;
        struct element *e = rng_element(parser, name,
                                        (struct xml){ attributes, c});
        if (e == NULL)
                content_free(parser, c);
        return e;
}

static struct element *
ns_name_element(const struct parser *parser, struct string uri,
                struct elements elements)
{
        struct attributes ns = { NULL, NULL };
        struct element *e = NULL;
        if (make_ns_attribute(&ns, parser, uri) &&
            (e = rng_element(parser, STRING("nsName"),
                             attributes_and_elements_to_xml(ns,
                                                            elements))) == NULL)
                attributes_free(parser, ns);
        return e;
}

static struct element *
ns_name_except_element(const struct parser *parser, struct string uri,
                       struct elements elements)
{
        struct element *ex, *e = NULL;
        if ((ex = rng_element(parser, STRING("except"),
                              elements_to_xml(elements))) != NULL &&
            (e = ns_name_element(parser, uri, element_to_elements(ex))) == NULL)
                parser->free(ex);
        return e;
}

static struct element *
name_element(const struct parser *parser, struct string uri, struct string name)
{
        struct attributes ns;
        struct content c = content_empty();
        struct element *e = NULL;
        if (make_ns_attribute(&ns, parser, uri) &&
            ((c = text(parser, name)).first == NULL ||
             (e = rng_element(parser, STRING("name"),
                              (struct xml){ns, c})) == NULL)) {
                content_free(parser, c);
                attributes_free(parser, ns);
        }
        return e;
}

static bool
xml_is_char(uc c)
{
        return c == 0x09 || (0x20 <= c && c <= 0xd7ff) ||
                (0x10000 <= c && c <= 0x10ffff);
}

static bool
xml_is_nc_name_start_char(uc c)
{
        return ('A' <= c && c <= 'Z') ||
                c == '_' ||
                ('a' <= c && c <= 'z') ||
                (0xc0 <= c && c <= 0xd6) ||
                (0xd8 <= c && c <= 0xf6) ||
                (0xf8 <= c && c <= 0x2ff) ||
                (0x370 <= c && c <= 0x37d) ||
                (0x37f <= c && c <= 0x1fff) ||
                (0x200c <= c && c <= 0x200d) ||
                (0x2070 <= c && c <= 0x218f) ||
                (0x2c00 <= c && c <= 0x2fef) ||
                (0x3001 <= c && c <= 0xd7ff) ||
                (0xf900 <= c && c <= 0xfdcf) ||
                (0xfdf0 <= c && c <= 0xfffd) ||
                (0x10000 <= c && c <= 0xeffff);
}

static bool
xml_is_nc_name_char(uc c)
{
        return xml_is_nc_name_start_char(c) ||
                c == '-' ||
                c == '.' ||
                ('0' <= c && c <= '9') ||
                c == 0xb7 ||
                (0x300 <= c && c <= 0x36f) ||
                (0x203f <= c && c <= 0x2040);
}

static int
yylex_literal(struct parser *parser, YYSTYPE *value, const YYLTYPE *location,
              struct io_dynamic_out *b, const char *p, const char *q,
              unsigned int d)
{
        if (b->n > 0)
                io_out_close(&b->self);
        value->literals.first =
                parser->realloc(NULL, sizeof(*value->literals.first));
        if (value->literals.first == NULL) {
                parser->free(b->s);
                return LITERAL;
        }
        value->literals.first->next = NULL;
        value->literals.first->string = b->n > 0 ?
                (struct string){ b->s, b->n, false } :
                (struct string){ p, (size_t)(q - p), true };
        value->literals.first->location = (struct location){
                { location->first.line, location->first.column + d },
                { location->last.line, location->last.column - d }
        };
        value->literals.last = value->literals.first;
        return LITERAL;
}

static int
yylex_bstring(YYSTYPE *value, struct io_dynamic_out *b, const char *p,
              const char *q, int token)
{
        if (b->n > 0) {
                io_out_close(&b->self);
                value->string = (struct string){ b->s, b->n, false };
        } else
                value->string = (struct string){ p, (size_t)(q - p), true };
        return token;
}

static const char *
parser_goto(struct parser *parser, const char *q, struct point *l)
{
        parser->l = *l;
        return parser->p = q;
}

static bool
yylex_decode(uc *c, bool *escape, const char **q, struct point *l,
             struct parser *parser)
{
        const char *t;
        *escape = false;
        *l = parser->l;
        while (parser->p < parser->end && !parser_has_enough_errors(parser)) {
                uc d = u_decode(q, parser->p, parser->end), n;
                switch (d) {
                case '\r':
                        if (*q < parser->end && **q == '\n') {
                                *escape = true;
                                (*q)++;
                        }
                case '\n':
                        return *c = '\0', l->line++, l->column = 1, true;
                case '\\':
                        if (*q == parser->end || **q != 'x')
                                return *c = d, l->column++, true;
                        t = *q + 1;
                        while (t < parser->end && *t == 'x')
                                t++;
                        if (t == parser->end || *t != '{')
                                return *c = '\\', l->column++, true;
                        for (n = 0, t++; t < parser->end; t++) {
                                uc a;
                                if ('0' <= *t && *t <= '9')
                                        a = (uc)*t - '0';
                                else if ('a' <= *t && *t <= 'f')
                                        a = 10 + (uc)*t - 'a';
                                else if ('A' <= *t && *t <= 'F')
                                        a = 10 + (uc)*t - 'A';
                                else
                                        break;
                                n *= 16;
                                n += a;
                        }
                        l->column += (size_t)(t - *q);
                        if (t == parser->end || *t != '}') {
                                if (!parser_error_s(parser, &(struct location){
                                                        parser->l, *l
                                                    },
                                                    "incomplete escape "
                                                    "sequence; skipping"))
                                        return false;
                                parser_goto(parser, t, l);
                                break;
                        }
                        d = n;
                        *escape = true;
                        *q = t + 1;
                        l->column++;
                        goto validate;
                case REPLACEMENT_CHARACTER:
                        if ((size_t)(*q - parser->p) !=
                            sizeof(u_replacement_character_s) ||
                            memcmp(parser->p, u_replacement_character_s,
                                   sizeof(u_replacement_character_s)) != 0) {
                                l->column += (size_t)(*q - parser->p) - 1;
                                if (!parser_error_s(parser, &(struct location){
                                                        parser->l, *l
                                                    },
                                                    "illegal UTF-8 byte "
                                                    "sequence; skipping"))
                                        return false;
                                l->column++;
                                parser_goto(parser, *q, l);
                                break;
                        }
                default:
                validate:
                        if (!xml_is_char(d)) {
                                // TODO Make these errors static?
                                char buf[UC_BYTES_MAX];
                                if (!parser_error(parser, &(struct location){
                                                        parser->l, *l
                                                  },
                                                  "character ‘%.*s’ ("UC_PRIU
                                                  ") isn’t allowed; skipping",
                                                  (int)uc_encode(buf,
                                                                 sizeof(buf), d),
                                                  buf, d))
                                        return false;
                                l->column++;
                                parser_goto(parser, *q, l);
                                break;
                        }
                        return *c = d, l->column++, true;
                }
        }
        return false;
}

static bool
yylex_append(struct io_dynamic_out *b, const char *p, const char *q, uc c,
             bool escape)
{
        if (b->n == 0) {
                if (!escape)
                        return true;
                else if (io_write(&b->self, p, (size_t)(q - p)) < 0)
                        return false;
        }
        char buf[UC_BYTES_MAX];
        return io_write(&b->self, buf, uc_encode(buf, sizeof(buf), c)) >= 0;
}

static int
yylex_nc_name(uc *c, bool *escape, struct io_dynamic_out *b, const char *p,
              const char **q, const char **t, struct point *l,
              struct parser *parser, YYLTYPE *location)
{
        if (!xml_is_nc_name_start_char(*c)) {
                location->last = parser->l;
                parser_goto(parser, *t, l);
                // TODO I guess we should really drop input until we
                // find something that we like.
                // TODO Only output if printable.
                char buf[UC_BYTES_MAX];
                // TODO Make these errors static?
                if (!parser_error(parser, location,
                                  "unexpected ‘%.*s’ ("UC_PRIU") in input; "
                                  "skipping",
                                  (int)uc_encode(buf, sizeof(buf), *c), buf, *c))
                        return -ENOMEM;
                return -EILSEQ;
        }
        do {
                if (!yylex_append(b, p, *q, *c, *escape))
                        return -ENOMEM;
                location->last = parser->l;
                *q = parser_goto(parser, *t, l);
        } while (yylex_decode(c, escape, t, l, parser) &&
                 xml_is_nc_name_char(*c));
        return 0;
}

static int lookup_keyword(YYSTYPE *value, const char *s, size_t n);

/* TODO Handle separator. (Note that we should really retain comments
 * for serialization purposes; Trang does it.) */
// TODO Handle documentation.
static int
yylex(YYSTYPE *value, YYLTYPE *location, struct parser *parser)
{
        uc c, d;
        bool escape, escaped;
        const char *p, *q, *t, *r;
        struct point l;
again:
        while (parser->p < parser->end)
                if (!yylex_decode(&c, &escape, &t, &l, parser))
                        return END;
                else if (c == '#') {
                        parser_goto(parser, t, &l);
                        while (parser->p < parser->end) {
                                if (!yylex_decode(&c, &escape, &t, &l, parser))
                                        return END;
                                parser_goto(parser, t, &l);
                                if (c == '\0' || c == '\x0a')
                                        break;
                        }
                } else if (c > ' ')
                        break;
                else
                        parser_goto(parser, t, &l);
        location->first = parser->l;
        if (parser->p == parser->end || parser_has_enough_errors(parser))
                return location->last = parser->l, END;
        escaped = false;
        struct io_dynamic_out b = IO_DYNAMIC_OUT_INIT(parser->realloc);
        switch (c) {
        case '"': case '\'':
                d = c;
                p = q = parser_goto(parser, t, &l);
                if (yylex_decode(&c, &escape, &t, &l, parser)) {
                        if (c == d) {
                                location->last = parser->l;
                                parser_goto(parser, t, &l);
                                if (!yylex_decode(&c, &escape, &t, &l,
                                                  parser) || c != d)
                                        return yylex_literal(parser, value,
                                                             location, &b, p, p,
                                                             1);
                                // Tripple string.
                                location->last = parser->l;
                                p = q = r = parser_goto(parser, t, &l);
                                int seen = 0;
                                bool q_escape = false;
                                while (seen < 3 &&
                                       yylex_decode(&c, &escape, &t, &l,
                                                    parser)) {
                                        if (c == d) {
                                                if (seen == 0)
                                                        q = r;
                                                seen++;
                                                if (escape)
                                                        q_escape = true;
                                        } else {
                                                for (; seen > 0; seen--)
                                                        if (!yylex_append(
                                                                    &b, p, q,
                                                                    d, q_escape))
                                                                goto oom;
                                                if (!yylex_append(&b, p, r, c,
                                                                  escape))
                                                        goto oom;
                                        }
                                        location->last = parser->l;
                                        r = parser_goto(parser, t, &l);
                                }
                                if (parser_has_enough_errors(parser))
                                        return location->last = parser->l, END;
                                else if (seen < 3) {
                                        if (c == '\0')
                                                location->last.column--;
                                        if (!parser_error_s(parser, location,
                                                            d == '"' ?
                                                            "expected “\"\"\"” "
                                                            "after literal "
                                                            "content" :
                                                            "expected “'''” "
                                                            "after literal "
                                                            "content"))
                                                goto oom;
                                        return yylex_literal(parser, value,
                                                             location, &b, p,
                                                             parser->end, 3);
                                }
                                return yylex_literal(parser, value, location, &b,
                                                     p, q, 3);
                        }
                        // Normal string.
                        while (c != d && c != '\0') {
                                if (!yylex_append(&b, p, q, c, escape))
                                        goto oom;
                                q = parser_goto(parser, t, &l);
                                if (!yylex_decode(&c, &escape, &t, &l, parser))
                                        break;
                        }
                }
                location->last = parser->l;
                if (parser_has_enough_errors(parser))
                        return END;
                else if (parser->p == parser->end || c == '\0') {
                        location->last.column--;
                        if (!parser_error_s(
                                    parser, location,
                                    d == '"' ?
                                    "expected ‘\"’ after literal content" :
                                    "expected ‘'’ after literal content"))
                                goto oom;
                } else
                        parser_goto(parser, t, &l);
                return yylex_literal(parser, value, location, &b, p, q, 1);
        case '=': case '{': case '}': case '(': case ')': case '[': case ']':
        case '+': case '?': case '*': case '-': case ',': case '~':
                location->last = parser->l;
                parser_goto(parser, t, &l);
                return (int)c;
        case '&':
                location->last = parser->l;
                parser_goto(parser, t, &l);
                if (yylex_decode(&c, &escape, &t, &l, parser) && c == '=') {
                        location->last = parser->l;
                        parser_goto(parser, t, &l);
                        return COMBINE_INTERLEAVE;
                } else if (parser_has_enough_errors(parser))
                        return END;
                return '&';
        case '|':
                location->last = parser->l;
                parser_goto(parser, t, &l);
                if (yylex_decode(&c, &escape, &t, &l, parser) && c == '=') {
                        location->last = parser->l;
                        parser_goto(parser, t, &l);
                        return COMBINE_CHOICE;
                } else if (parser_has_enough_errors(parser))
                        return END;
                return '|';
        case '>':
                location->last = parser->l;
                parser_goto(parser, t, &l);
                if (yylex_decode(&c, &escape, &t, &l, parser) && c == '>') {
                        location->last = parser->l;
                        parser_goto(parser, t, &l);
                } else if (parser_has_enough_errors(parser))
                        return END;
                else if (!parser_error_s(parser, location,
                                         "stray ‘>’ in input; interpreting it "
                                         "as “>>”"))
                        goto oom;
                return FOLLOW_ANNOTATION;
        case '\\':
                escaped = true;
                location->last = parser->l;
                p = q = parser_goto(parser, t, &l);
                if (!yylex_decode(&c, &escape, &t, &l, parser)) {
                        parser_error_s(parser, location,
                                       "unexpected ‘\\’ (U+005C) at end of "
                                       "input");
                        return END;
                }
                break;
        default:
                p = q = parser->p;
                break;
        }
        switch (yylex_nc_name(&c, &escape, &b, p, &q, &t, &l, parser,
                              location)) {
        case -EILSEQ: goto again;
        case -ENOMEM: goto oom;
        }
        if (!escaped && c == ':') {
                value->q_name.prefix_location = *location;
                if (b.n > 0) {
                        io_out_close(&b.self);
                        value->q_name.prefix =
                                (struct string){ b.s, b.n, false };
                } else
                        value->q_name.prefix =
                                (struct string){ p, (size_t)(q - p), true };
                location->last = parser->l;
                r = parser_goto(parser, t, &l);
                if (!yylex_decode(&c, &escape, &t, &l, parser) || c <= ' ') {
                        if (!parser_error_s(parser, location,
                                            "incomplete CName; treating it as "
                                            "*"))
                                goto oom;
                        value->q_name.local = STRING("");
                        return NS_NAME;
                } else if (c == '*') {
                        location->last = parser->l;
                        parser_goto(parser, t, &l);
                        value->q_name.local = STRING("");
                        return NS_NAME;
                }
                b = IO_DYNAMIC_OUT_INIT(parser->realloc);
                p = q = r;
                switch (yylex_nc_name(&c, &escape, &b, p, &q, &t, &l, parser,
                                      location)) {
                case -EILSEQ: goto again;
                case -ENOMEM: goto oom;
                }
                if (b.n > 0) {
                        io_out_close(&b.self);
                        value->q_name.local = (struct string){ b.s, b.n, false };
                } else
                        value->q_name.local =
                                (struct string){ p, (size_t)(q - p), true };
                return C_NAME;
        } else if (!escaped) {
                int token = lookup_keyword(value,
                                           b.n > 0 ? b.s : p,
                                           b.n > 0 ? b.n : (size_t)(q - p));
                if (token > 0) {
                        parser->free(b.s);
                        return token;
                }
        }
        return yylex_bstring(value, &b, p, q, IDENTIFIER);
oom:
        parser->free(b.s);
        return END;
}

static void
yyerror(YYLTYPE *location, struct parser *parser, const char *message)
{
        parser_error(parser, location, "%s", message);
}
}

%define api.pure full
%parse-param {struct parser *parser}
%lex-param {struct parser *parser}
%name-prefix "_rncc_"
%token-table
%debug
%define parse.error verbose
%expect 0
%locations

%token
  END 0 "end of file"
  <keyword> ATTRIBUTE "attribute"
  <keyword> DATATYPES "datatypes"
  <keyword> DEFAULT "default"
  <keyword> DIV "div"
  <keyword> ELEMENT "element"
  <keyword> EMPTY "empty"
  <keyword> EXTERNAL "external"
  <keyword> GRAMMAR "grammar"
  <keyword> INCLUDE "include"
  <keyword> INHERIT "inherit"
  <keyword> LIST "list"
  <keyword> MIXED "mixed"
  <keyword> NAMESPACE "namespace"
  <keyword> NOTALLOWED "notAllowed"
  <keyword> PARENT "parent"
  <keyword> START "start"
  <keyword> TSTRING "string"
  <keyword> TEXT "text"
  <keyword> TOKEN "token"
  COMBINE_CHOICE "|="
  COMBINE_INTERLEAVE "&="
  FOLLOW_ANNOTATION ">>"
  <string> DOCUMENTATION "documentation"
  <q_name> C_NAME "CName"
  <q_name> NS_NAME "NsName"
  <literals> LITERAL "literal"
  <string> IDENTIFIER "identifier"
;

%type <attribute> annotation_attribute nested_annotation_attribute
%type <attributes> assign_op opt_inherit datatype_name annotation_attributes
%type <attributes> nested_annotation_attributes
%type <literals> literal literal_segments
%type <content> param_value annotation_content documentation
%type <element> top_level_body member annotated_component component
%type <element> start define include include_member annotated_include_component
%type <element> include_component div include_div repeated_primary
%type <element> lead_annotated_data_except primary data_except annotated_param
%type <element> param except_element_name_class except_attribute_name_class
%type <element> simple_element_name_class simple_attribute_name_class
%type <element> simple_name_class annotation_element
%type <element> annotation_element_not_keyword nested_annotation_element
%type <elements> grammar top_level_grammar opt_include_body include_body pattern
%type <elements> top_level_pattern inner_pattern top_level_inner_pattern
%type <elements> particle_choice particle_group particle_interleave particle
%type <elements> inner_particle top_level_inner_particle annotated_primary
%type <elements> top_level_annotated_primary annotated_data_except
%type <elements> top_level_annotated_data_except lead_annotated_primary
%type <elements> opt_params params element_name_class attribute_name_class
%type <elements> element_name_class_choice attribute_name_class_choice
%type <elements> annotated_simple_element_name_class
%type <elements> annotated_simple_attribute_name_class
%type <elements> lead_annotated_simple_element_name_class
%type <elements> lead_annotated_simple_attribute_name_class follow_annotations
%type <elements> annotation_elements documentations
%type <keyword> keyword
%type <name> foreign_attribute_name foreign_element_name
%type <name> foreign_element_name_not_keyword any_attribute_name any_element_name
%type <name> prefixed_name
%type <q_name> c_name
%type <string> namespace_uri_literal
%type <string> namespace_prefix datatype_prefix any_uri_literal ref
%type <string> datatype_value identifier_or_keyword
%type <string> identifier
%type <xml> nested_annotation_attributes_and_annotation_content
%type <xml> annotation_attributes_and_elements
%type <xml> annotations annotation_attributes_content

%printer { fprintf(yyoutput, "="); } '='
%printer { fprintf(yyoutput, "{"); } '{'
%printer { fprintf(yyoutput, "}"); } '}'
%printer { fprintf(yyoutput, "("); } '('
%printer { fprintf(yyoutput, ")"); } ')'
%printer { fprintf(yyoutput, "["); } '['
%printer { fprintf(yyoutput, "]"); } ']'
%printer { fprintf(yyoutput, "+"); } '+'
%printer { fprintf(yyoutput, "?"); } '?'
%printer { fprintf(yyoutput, "*"); } '*'
%printer { fprintf(yyoutput, "-"); } '-'
%printer { fprintf(yyoutput, ","); } ','
%printer { fprintf(yyoutput, "~"); } '~'
%printer { fprintf(yyoutput, "&"); } '&'
%printer { fprintf(yyoutput, "|"); } '|'
%printer { fprintf(yyoutput, "\\"); } '\\'

%code
{
#define MAYBEABORT do { \
        if (parser_has_enough_errors(parser)) { \
                YYABORT; \
        } \
} while (0)
#define B(p) do { \
        if (!(p) && parser_has_enough_errors(parser)) { \
                YYABORT; \
        } \
} while (0)
#define F(p, l, m) do {                         \
        if (!(p)) { \
                if (!parser_error_s(parser, &(l), m)) { \
                        YYABORT; \
                } \
        } \
} while (0)
#define MB(p) do { \
        if (!(p)) { \
                parser_oom(parser, &(struct location){ parser->l, parser->l }); \
                YYABORT; \
        } \
} while (0)
#define M(p) MB((p) != NULL)
#define L(p) M((p).last)
#define S(p) M((p).s)

#ifdef HAVE_WCONVERSION
#  pragma GCC diagnostic push
#  pragma GCC diagnostic ignored "-Wconversion"
#endif
}

%%

top_level: preamble top_level_body { parser->top_level = $2; };

preamble:
  %empty
| preamble decl
| preamble error;

decl:
  "namespace" namespace_prefix '=' namespace_uri_literal
    { B(bind_prefix(parser, location_join(@1, @4), $2, &@2, $4, &@4)); }
| "default" "namespace" '=' namespace_uri_literal
    { B(bind_default(parser, location_join(@1, @4), $4, &@4)); }
| "default" "namespace" namespace_prefix '=' namespace_uri_literal
    { B(bind_prefix(parser, location_join(@1, @5), $3, &@3, $5, &@5));
      B(bind_default(parser, location_join(@1, @5), $5, &@5)); }
| "datatypes" datatype_prefix '=' literal
    { B(bind_datatype_prefix(parser, location_join(@1, @4), $2, $4, &@4)); }

namespace_prefix:
  identifier_or_keyword
    { F(string_cmp($1, prefix_xmlns) != 0, @1,
        "namespace prefix must not be “xmlns”");
      $$ = $1; }

datatype_prefix: identifier_or_keyword;

namespace_uri_literal:
  literal { S($$ = literals_to_string(parser, $1)); }
| "inherit" { $$ = inherit; };

top_level_body:
  %empty
    { M($$ = rng_element(parser, STRING("grammar"), empty())); }
| top_level_grammar
    { M($$ = rng_element(parser, STRING("grammar"), elements_to_xml($1))); }
| top_level_pattern
    { assert($1.last == $1.first);
      $$ = $1.first; }

top_level_grammar:
  member { $$ = element_to_elements($1); }
| top_level_grammar member { $$ = elements_append($1, $2); };

member: annotated_component
| annotation_element_not_keyword;

annotated_component: annotations component { $$ = apply_annotations($1, $2); };

component: start
| define
| include
| div;

start:
  "start" assign_op pattern
    { M($$ = rng_element(parser, $1, attributes_and_elements_to_xml($2, $3)));};

define:
  identifier assign_op pattern
    { M($$ = rng_element_with_attribute(parser, STRING("define"), STRING("name"),
                                        $1, $2, elements_to_content($3))); }

assign_op:
  '='
    { $$ = empty().attributes; }
| "|="
    { L($$ = attribute_to_attributes(attribute(parser, LNAME("combine"),
                                               STRING("choice")))); }
| "&="
    { L($$ = attribute_to_attributes(attribute(parser, LNAME("combine"),
                                               STRING("interleave")))); };

include:
  "include" any_uri_literal opt_inherit opt_include_body
    { M($$ = rng_element_with_attribute(parser, $1, STRING("href"),
                                        map_schema_ref(&parser->environment, $2),
                                        $3, elements_to_content($4))); };

any_uri_literal:
  literal
    { S($$ = literals_to_string(parser, $1));
      struct uri u = URI_INIT;
      size_t n = parser->errors->n;
      const char *end;
      int r = uri_parse(&u, parser->errors, &end, $$.s, $$.n);
      if (end != $$.s + $$.n) {
              parser_error_s(parser, &(struct location){
                                  {1, (size_t)(end - $$.s) + 1},
                                  {1, (size_t)(end - $$.s) + 1}
                             }, "invalid URI content starting here");
              if (r == 0)
                      r = -EILSEQ;
      }
      adjust_uri_errors(parser, n, $1);
      B(r >= 0); };

opt_inherit:
  %empty
    { MB(make_ns_attribute(&$$, parser, lookup_default(&parser->environment))); }
| "inherit" '=' identifier_or_keyword
    { struct string uri = STRING("");
      B(lookup_prefix(&uri, parser, &@3, $3));
      MB(make_ns_attribute(&$$, parser, uri)); };

opt_include_body:
  %empty { $$ = elements_empty(); }
| '{' include_body '}' { $$ = $2; };

include_body:
  %empty { $$ = elements_empty(); }
| include_body include_member { $$ = elements_append($1, $2); };

include_member: annotated_include_component | annotation_element_not_keyword;

annotated_include_component:
  annotations include_component { $$ = apply_annotations($1, $2); };

include_component: start | define | include_div;

div:
  "div" '{' grammar '}'
    { M($$ = rng_element(parser, $1, elements_to_xml($3))); };

grammar:
  %empty { $$ = elements_empty(); }
| grammar member { $$ = elements_append($1, $2); };

include_div:
  "div" '{' include_body '}'
    { M($$ = rng_element(parser, $1, elements_to_xml($3))); };

pattern: inner_pattern;

top_level_pattern: top_level_inner_pattern;

inner_pattern:
  inner_particle
| particle_choice
    { L($$ = element_to_elements(rng_element(parser, STRING("choice"),
                                             elements_to_xml($1)))); }
| particle_group
    { L($$ = element_to_elements(rng_element(parser, STRING("group"),
                                             elements_to_xml($1)))); }
| particle_interleave
    { L($$ = element_to_elements(rng_element(parser, STRING("interleave"),
                                             elements_to_xml($1)))); }
| annotated_data_except;

top_level_inner_pattern:
  top_level_inner_particle
| particle_choice
    { L($$ = element_to_elements(rng_element(parser, STRING("choice"),
                                             elements_to_xml($1)))); }
| particle_group
    { L($$ = element_to_elements(rng_element(parser, STRING("group"),
                                             elements_to_xml($1)))); }
| particle_interleave
    { L($$ = element_to_elements(rng_element(parser, STRING("interleave"),
                                             elements_to_xml($1)))); }
| top_level_annotated_data_except;

particle_choice:
  particle '|' particle { $$ = elements_concat($1, $3); }
| particle_choice '|' particle { $$ = elements_concat($1, $3); };

particle_group:
  particle ',' particle { $$ = elements_concat($1, $3); }
| particle_group ',' particle { $$ = elements_concat($1, $3); };

particle_interleave:
  particle '&' particle { $$ = elements_concat($1, $3); }
| particle_interleave '&' particle { $$ = elements_concat($1, $3); };

particle: inner_particle;

inner_particle:
  annotated_primary
| repeated_primary follow_annotations { $$ = elements_cons($1, $2); };

top_level_inner_particle:
  top_level_annotated_primary
| repeated_primary { $$ = element_to_elements($1); };

repeated_primary:
  annotated_primary '*'
    { M($$ = rng_element(parser, STRING("zeroOrMore"), elements_to_xml($1))); }
| annotated_primary '+'
    { M($$ = rng_element(parser, STRING("oneOrMore"), elements_to_xml($1))); }
| annotated_primary '?'
    { M($$ = rng_element(parser, STRING("optional"), elements_to_xml($1))); };

annotated_primary:
  lead_annotated_primary follow_annotations { $$ = elements_concat($1, $2); };

top_level_annotated_primary: lead_annotated_primary;

annotated_data_except:
  lead_annotated_data_except follow_annotations { $$ = elements_cons($1, $2); };

top_level_annotated_data_except:
  lead_annotated_data_except { $$ = element_to_elements($1); };

lead_annotated_data_except:
  annotations data_except { $$ = apply_annotations($1, $2); };

lead_annotated_primary:
  annotations primary { $$ = element_to_elements(apply_annotations($1, $2)); };
| annotations '(' inner_pattern ')'
    { L($$ = name_cmp($3.first->name, NAME(uri_rng, STRING("zeroOrMore"))) == 0 ||
             name_cmp($3.first->name, NAME(uri_rng, STRING("oneOrMore"))) == 0 ||
             name_cmp($3.first->name, NAME(uri_rng, STRING("optional"))) == 0 ||
             name_cmp($3.first->name, NAME(uri_rng, STRING("choice"))) == 0 ||
             name_cmp($3.first->name, NAME(uri_rng, STRING("group"))) == 0 ||
             name_cmp($3.first->name, NAME(uri_rng, STRING("interleave"))) == 0 ?
                      element_to_elements(apply_annotations($1, $3.first)) :
                      apply_annotations_group(parser, $1, $3)); };

primary:
  "element" element_name_class '{' pattern '}'
    { M($$ = rng_element(parser, $1,
                         elements_to_xml(elements_concat($2, $4)))); }
| "attribute" attribute_name_class '{' pattern '}'
    { M($$ = rng_element(parser, $1,
                         elements_to_xml(elements_concat($2, $4)))); }
| "mixed" '{' pattern '}'
    { M($$ = rng_element(parser, $1, elements_to_xml($3))); }
| "list" '{' pattern '}'
    { M($$ = rng_element(parser, $1, elements_to_xml($3))); }
| datatype_name opt_params
    { M($$ = rng_element(parser, STRING("data"),
                         attributes_and_elements_to_xml($1, $2))); }
| datatype_name datatype_value
    { M($$ = rng_element_with_text(parser, STRING("value"), $1, $2)); }
| datatype_value
    { M($$ = rng_element_with_text(parser, STRING("value"), empty().attributes,
                                  $1)); }
| "empty"
    { M($$ = rng_element(parser, $1, empty())); }
| "notAllowed"
    { M($$ = rng_element(parser, $1, empty())); }
| "text"
    { M($$ = rng_element(parser, $1, empty())); }
| ref
    { M($$ = rng_element_with_attribute(parser, STRING("ref"), STRING("name"),
                                        $1, empty().attributes,
                                        content_empty())); }
| "parent" ref
    { M($$ = rng_element_with_attribute(parser, STRING("parentRef"),
                                        STRING("name"), $2, empty().attributes,
                                        content_empty())); }
| "grammar" '{' grammar '}'
    { M($$ = rng_element(parser, $1, elements_to_xml($3))); }
| "external" any_uri_literal opt_inherit
    { M($$ = rng_element_with_attribute(parser, STRING("externalRef"),
                                        STRING("href"),
                                        map_schema_ref(&parser->environment, $2),
                                        $3, content_empty())); };

data_except:
  datatype_name opt_params '-' lead_annotated_primary
    { M($$ = rng_element_with_element(parser, STRING("data"), $1, $2,
                                      STRING("except"), $4)); };

ref: identifier;

datatype_name:
  c_name
    { struct string uri = STRING("");
      B(lookup_datatype_prefix(&uri, parser, &$1.prefix_location, $1.prefix));
      L($$ = datatype_attributes(parser, uri, $1.local)); }
| "string"
    { L($$ = datatype_attributes(parser, STRING(""), $1)); }
| "token"
    { L($$ = datatype_attributes(parser, STRING(""), $1)); };

datatype_value: literal { S($$ = literals_to_string(parser, $1)); }

opt_params:
  %empty { $$ = elements_empty(); }
| '{' params '}' { $$ = $2; };

params:
  %empty { $$ = elements_empty(); }
| params annotated_param { $$ = elements_append($1, $2); };

annotated_param: annotations param { $$ = apply_annotations($1, $2); };

param:
  identifier_or_keyword '=' param_value
    { M($$ = rng_element_with_attribute(parser, STRING("param"),
                                        STRING("name"), $1,
                                        empty().attributes, $3)); };

param_value: literal { L($$ = text(parser, literals_to_string(parser, $1))); };

element_name_class:
  annotated_simple_element_name_class
| element_name_class_choice
    { L($$ = element_to_elements(rng_element(parser, STRING("choice"),
                                             elements_to_xml($1)))); }
| annotations except_element_name_class follow_annotations
    { $$ = elements_cons(apply_annotations($1, $2), $3); };

attribute_name_class:
  annotated_simple_attribute_name_class
| attribute_name_class_choice
    { L($$ = element_to_elements(rng_element(parser, STRING("choice"),
                                             elements_to_xml($1)))); }
| annotations except_attribute_name_class follow_annotations
    { $$ = elements_cons(apply_annotations($1, $2), $3); };

element_name_class_choice:
  annotated_simple_element_name_class '|' annotated_simple_element_name_class
    { $$ = elements_concat($1, $3); }
| element_name_class_choice '|' annotated_simple_element_name_class
    { $$ = elements_concat($1, $3); };

attribute_name_class_choice:
  annotated_simple_attribute_name_class '|' annotated_simple_attribute_name_class
    { $$ = elements_concat($1, $3); }
| attribute_name_class_choice '|' annotated_simple_attribute_name_class
    { $$ = elements_concat($1, $3); };

annotated_simple_element_name_class:
  lead_annotated_simple_element_name_class follow_annotations
    { $$ = elements_concat($1, $2); };

annotated_simple_attribute_name_class:
  lead_annotated_simple_attribute_name_class follow_annotations
    { $$ = elements_concat($1, $2); };

lead_annotated_simple_element_name_class:
  annotations simple_element_name_class
    { $$ = element_to_elements(apply_annotations($1, $2)); }
| annotations '(' element_name_class ')'
    { L($$ = name_cmp($3.first->name, NAME(uri_rng, STRING("choice"))) == 0 ?
                      element_to_elements(apply_annotations($1, $3.first)) :
                      apply_annotations_choice(parser, $1, $3)); };

lead_annotated_simple_attribute_name_class:
  annotations simple_attribute_name_class
    { $$ = element_to_elements(apply_annotations($1, $2)); }
| annotations '(' attribute_name_class ')'
    { L($$ = name_cmp($3.first->name, NAME(uri_rng, STRING("choice"))) == 0 ?
                      element_to_elements(apply_annotations($1, $3.first)) :
                      apply_annotations_choice(parser, $1, $3)); };

except_element_name_class:
  NS_NAME '-' lead_annotated_simple_element_name_class
    { struct string uri = STRING("");
      B(lookup_prefix(&uri, parser, &$1.prefix_location, $1.prefix));
      M($$ = ns_name_except_element(parser, uri, $3)); }
| '*' '-' lead_annotated_simple_element_name_class
    { M($$ = rng_element_with_element(parser, STRING("anyName"),
                                      empty().attributes, elements_empty(),
                                      STRING("except"), $3)); };

except_attribute_name_class:
  NS_NAME '-' lead_annotated_simple_attribute_name_class
    { struct string uri = STRING("");
      B(lookup_prefix(&uri, parser, &$1.prefix_location, $1.prefix));
      M($$ = ns_name_except_element(parser, uri, $3)); }
| '*' '-' lead_annotated_simple_attribute_name_class
    { M($$ = rng_element_with_element(parser, STRING("anyName"),
                                      empty().attributes, elements_empty(),
                                      STRING("except"), $3)); };

simple_element_name_class:
  identifier_or_keyword
    { M($$ = name_element(parser, lookup_default(&parser->environment), $1)); }
| simple_name_class;

simple_attribute_name_class:
  identifier_or_keyword { M($$ = name_element(parser, STRING(""), $1)); }
| simple_name_class;

simple_name_class:
  c_name
    { struct string uri = STRING("");
      B(lookup_prefix(&uri, parser, &$1.prefix_location, $1.prefix));
      M($$ = name_element(parser, uri, $1.local)); }
| NS_NAME
    { struct string uri = STRING("");
      B(lookup_prefix(&uri, parser, &$1.prefix_location, $1.prefix));
      M($$ = ns_name_element(parser, uri, elements_empty())); }
| '*'
    { M($$ = rng_element(parser, STRING("anyName"), empty())); };

follow_annotations:
  %empty { $$ = elements_empty(); }
| follow_annotations ">>" annotation_element { $$ = elements_append($1, $3); };

annotations:
  documentations
    { $$ = elements_to_xml($1); }
| documentations '[' annotation_attributes_and_elements ']'
  { $$ = concat(elements_to_xml($1), $3); };

annotation_attributes_and_elements:
  %empty
    { $$ = empty(); }
| annotation_attributes
    { B(attributes_check_for_duplicates($1, parser));
      $$ = attributes_to_xml($1); }
| annotation_attributes annotation_elements
    { B(attributes_check_for_duplicates($1, parser));
      $$ = attributes_and_elements_to_xml($1, $2); }
| annotation_elements
    { $$ = elements_to_xml($1); };

annotation_attributes:
  annotation_attribute { $$ = attribute_to_attributes($1); }
| annotation_attributes annotation_attribute { $$ = attributes_append($1, $2); };

annotation_attribute:
  foreign_attribute_name '=' literal
    { M($$ = foreign_attribute(parser, location_join(@1, @3), $1,
                               literals_to_string(parser, $3))); };

foreign_attribute_name:
  prefixed_name
    { F(string_cmp($1.uri, uri_xmlns) != 0, @1,
        "annotation attribute can’t have namespace URI "
        "“http://www.w3.org/2000/xmlns”");
      F(string_cmp($1.uri, STRING("")) != 0, @1,
        "annotation attribute must have a namespace URI");
      F(string_cmp($1.uri, uri_rng) != 0, @1,
        "annotation attribute can’t have namespace URI "
        "“http://relaxng.org/ns/structure/1.0”");
      $$ = $1; };

annotation_elements:
  annotation_element { $$ = element_to_elements($1); }
| annotation_elements annotation_element { $$ = elements_append($1, $2); };

annotation_element:
  foreign_element_name annotation_attributes_content
    { $$ = element(parser, $1, $2); };

foreign_element_name:
  foreign_element_name_not_keyword
| keyword { $$ = name(STRING(""), $1); };

/* To avoid shift/reduce, we add annotations here and then generate a
 * syntax error if it isn’t empty. */
annotation_element_not_keyword:
  annotations foreign_element_name_not_keyword annotation_attributes_content
    { if ($1.attributes.first != NULL || $1.content.first != NULL) {
              parser_error_s(parser, &@2,
                             "annotation element can’t itself have annotations");
      } else {
              assert($1.attributes.last == NULL);
              assert($1.content.last == NULL);
      }
      M($$ = element(parser, $2, $3)); };

foreign_element_name_not_keyword:
  identifier
    { $$ = name(STRING(""), $1); }
| prefixed_name
  { F(string_cmp($1.uri, uri_rng) != 0, @1,
        "annotation element can’t have namespace URI "
        "“http://relaxng.org/ns/structure/1.0”");
      $$ = $1; };

annotation_attributes_content:
  '[' nested_annotation_attributes_and_annotation_content ']' { $$ = $2; };

nested_annotation_attributes_and_annotation_content:
  %empty
    { $$ = empty(); }
| nested_annotation_attributes
    { B(attributes_check_for_duplicates($1, parser));
      $$ = attributes_to_xml($1); }
| nested_annotation_attributes annotation_content
    { B(attributes_check_for_duplicates($1, parser));
      $$ = (struct xml){ $1, $2 }; }
| annotation_content
    { $$ = (struct xml){ empty().attributes, $1 }; };

nested_annotation_attributes:
  nested_annotation_attribute
    { $$ = attribute_to_attributes($1); }
| nested_annotation_attributes nested_annotation_attribute
    { $$ = attributes_append($1, $2); };

nested_annotation_attribute:
  any_attribute_name '=' literal
    { M($$ = foreign_attribute(parser, location_join(@1, @3), $1,
                               literals_to_string(parser, $3))); };

any_attribute_name:
  identifier_or_keyword
    { $$ = name(STRING(""), $1); }
| prefixed_name
    { F(string_cmp($1.uri, uri_xmlns) != 0, @1,
        "annotation attribute can’t have namespace URI "
        "“http://www.w3.org/2000/xmlns”");
      $$ = $1; };

annotation_content:
  annotation_element
    { $$ = element_to_xml($1).content; }
| literal
    { L($$ = text(parser, literals_to_string(parser, $1))); }
| annotation_content nested_annotation_element
    { $$ = content_concat($1, element_to_xml($2).content); }
| annotation_content literal
    { L($$ = content_concat($1, text(parser,
                                     literals_to_string(parser, $2)))); };

nested_annotation_element:
  any_element_name annotation_attributes_content
    { M($$ = element(parser, $1, $2)); };

any_element_name:
  identifier_or_keyword { $$ = name(STRING(""), $1); }
| prefixed_name;

prefixed_name:
  c_name
    { struct string uri = STRING("");
      B(use_prefix(&uri, parser, &$1.prefix_location, $1.prefix));
      F(!string_is_inherit(uri), @1,
        "namespace URI for annotation can’t be inherited");
      $$ = name(uri, $1.local); };

documentations:
  %empty
    { $$ = elements_empty(); }
| documentations documentation
    { L($$ = elements_append($1,
                             element(parser, name_documentation,
                                     (struct xml){empty().attributes, $2}))); };

identifier_or_keyword: identifier | keyword { $$ = $1; };

keyword:
  "attribute"
| "datatypes"
| "default"
| "div"
| "element"
| "empty"
| "external"
| "grammar"
| "include"
| "inherit"
| "list"
| "mixed"
| "namespace"
| "notAllowed"
| "parent"
| "start"
| "string"
| "text"
| "token";

literal: LITERAL { L($$ = $1); } | literal_segments;

literal_segments:
  LITERAL '~' LITERAL { L($1); L($3); $$ = literals_concat($1, $3); }
| literal_segments '~' LITERAL { L($3); $$ = literals_concat($1, $3); }

identifier: IDENTIFIER { S($$ = $1); }

c_name: C_NAME { $$ = $1; S($$.prefix); S($$.local); }

documentation: DOCUMENTATION { S($1); L($$ = text(parser, $1)); }

%%

#ifdef HAVE_WCONVERSION
#  pragma GCC diagnostic pop
#endif

struct action {
        bool enter;
        struct child *children;
};

#define PREFIX action_
#define TYPE struct action
#include "recstack.h"

static int
child_traverse(struct child *child, int (*enter)(struct child *, void *),
               int (*leave)(struct child *, void *), void *closure)
{
        if (child == NULL)
                return 0;
        int r = 0;
        struct action_recstack actions = RECSTACK_INIT(actions);
        if ((r = action_recstack_push(&actions,
                                      &(struct action){true, child})) < 0)
                return r;
        while (actions.n > 0)
                if (actions.s[actions.n-1].enter) {
                        struct child *p = actions.s[actions.n-1].children;
                        actions.s[actions.n-1].children = p->next;
                        if (actions.s[actions.n-1].children == NULL)
                                actions.n--;
                        if ((r = enter(p, closure)) < 0)
                                break;
                        if ((r = action_recstack_push(&actions, &(struct action){
                                                              false, p
                                                      })) < 0 ||
                            (p->type == CHILD_TYPE_ELEMENT &&
                             ((struct element *)p)->children.first != NULL &&
                             (r = action_recstack_push(
                                     &actions,
                                     &(struct action){
                                            true,
                                            ((struct element *)p)->children.first
                                     })) < 0))
                                break;
                } else {
                        if ((r = leave(actions.s[actions.n-1].children,
                                       closure)) < 0)
                                break;
                        actions.n--;
                }
        action_recstack_free(&actions);
        return r;
}

#define PREFIX bool_
#define TYPE bool
#include "recstack.h"

struct xml_closure {
        struct environment *environment;
        struct bool_recstack indent;
        struct io_out *out;
};

#define OUTS(closure, s) io_write((closure)->out, s, lengthof(s) - 1)

static int
outname(struct xml_closure *closure, struct name name)
{
        struct namespace_mapping *p = NULL;
        if (name.uri.n > 0)
                if (string_cmp(name.uri, uri_rng) != 0) {
                        for (p = closure->environment->ns; p != NULL; p=p->next)
                                if (string_cmp(p->uri, name.uri) == 0)
                                        break;
                        assert(p != NULL ||
                               string_cmp(name.uri,
                                          closure->environment->d.uri) == 0);
                }
        int r;
        if (p != NULL && p->prefix.n > 0 &&
            ((r = io_write(closure->out, p->prefix.s, p->prefix.n)) < 0 ||
             (r = OUTS(closure, ":")) < 0))
                return r;
        return io_write(closure->out, name.local.s, name.local.n);
}

static int
indent(struct xml_closure *closure, size_t n)
{
        int r;
        static char cs[] = {
                ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
                ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
                ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
                ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
                ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
                ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
                ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
                ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
                ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
                ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
                ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
                ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
                ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
                ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
                ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
                ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
        };
        for (size_t i = n, m; i > 0; i -= m) {
                m = i < lengthof(cs) / 2 ? i : lengthof(cs) / 2;
                if ((r = io_write(closure->out, cs, 2 * m)) < 0)
                        return r;
        }
        return 0;
}

struct entity {
        const char *s;
        size_t n;
};

#define E(s) { s, sizeof(s) - 1 }
#define N { NULL, 0 }
static const struct entity text_entities[] = {
        E("\n"),N,N,N,N,N,N,N,N,N,N,N,N,N,N,N,
        N,N,N,N,N,N,N,N,N,N,N,N,N,N,N,N,
        N,N,N,N,N,N,E("&amp;"),N,N,N,N,N,N,N,N,N,
        N,N,N,N,N,N,N,N,N,N,N,N,E("&lt;")
};

static const struct entity attribute_entities[] = {
        E("\n"),N,N,N,N,N,N,N,N,N,N,N,N,N,N,N,
        N,N,N,N,N,N,N,N,N,N,N,N,N,N,N,N,
        N,N,E("&quot;"),N,N,N,E("&amp;"),N,N,N,N,N,N,N,N,N,
        N,N,N,N,N,N,N,N,N,N,N,N,E("&lt;"),N,E("&gt;")
};
#undef N
#undef E

static int
escape(struct xml_closure *closure, struct string string,
       const struct entity *entities, size_t n_entities)
{
        int r;
        const char *p = string.s, *q = p, *end = q + string.n;
        while (q < end) {
                const struct entity *e;
                if ((unsigned char)*q < n_entities &&
                    (e = &entities[(unsigned char)*q])->n > 0) {
                        if ((r = io_write(closure->out, p,
                                          (size_t)(q - p))) < 0 ||
                            (r = io_write(closure->out, e->s, e->n)) < 0)
                                return r;
                        p = q + 1;
                }
                q++;
        }
        return io_write(closure->out, p, (size_t)(q - p));
}

static int
outnamespace(struct xml_closure *closure, struct namespace_mapping *p)
{
        int r;
        return (r = OUTS(closure, " xmlns:")) < 0 ||
                (r = io_write(closure->out, p->prefix.s, p->prefix.n)) < 0 ||
                (r = OUTS(closure, "=\"")) < 0 ||
                (r = escape(closure, p->uri, attribute_entities,
                            lengthof(attribute_entities))) < 0 ||
                (r = OUTS(closure, "\"")) < 0 ? r : 0;
}

static int
xml_enter_element(struct element *element, struct xml_closure *closure)
{
        int r;
        if ((closure->indent.s[closure->indent.n-1] &&
             (r = indent(closure, closure->indent.n)) < 0) ||
            (r = OUTS(closure, "<")) < 0 ||
            (r = outname(closure, element->name)) < 0)
                return r;
        if (closure->indent.n == 0) {
                if ((r = OUTS(closure, " xmlns=\"")) < 0 ||
                    (r = escape(closure, element->name.uri, attribute_entities,
                                lengthof(attribute_entities))) < 0 ||
                    (r = OUTS(closure, "\"")) < 0)
                        return r;
                list_for_each(struct namespace_mapping, p,
                              closure->environment->ns)
                        if (p->used && (r = outnamespace(closure, p)) < 0)
                                return r;
        }
        list_for_each(struct attribute, p, element->attributes.first)
                if ((r = io_write(closure->out, " ", 1)) < 0 ||
                    (r = outname(closure, p->name)) < 0 ||
                    (r = OUTS(closure, "=\"")) < 0 ||
                    (r = escape(closure, p->value, attribute_entities,
                                lengthof(attribute_entities))) < 0 ||
                    (r = OUTS(closure, "\"")) < 0)
                        return r;
        bool t = closure->indent.n == 0 ||
                closure->indent.s[closure->indent.n-1];
        if ((r = bool_recstack_push(&closure->indent, &t)) < 0)
                return r;
        if (closure->indent.s[closure->indent.n-1]) {
                list_for_each(struct child, p, element->children.first)
                        if (p->type == CHILD_TYPE_TEXT) {
                                closure->indent.s[closure->indent.n-1] = false;
                                break;
                        }
                if (closure->indent.s[closure->indent.n-1] &&
                    element->children.first == NULL)
                        closure->indent.s[closure->indent.n-1] = false;
        }
        return (element->children.first == NULL &&
                (r = OUTS(closure, "/")) < 0) ||
                (r = OUTS(closure, ">")) < 0 ||
                (closure->indent.s[closure->indent.n-1] &&
                 (r = OUTS(closure, "\n")) < 0) ? r : 0;
}

static int
xml_enter_text(struct text *text, struct xml_closure *closure)
{
        return escape(closure, text->string, text_entities,
                      lengthof(text_entities));
}

static int
xml_enter(struct child *child, void *closure)
{
        switch (child->type) {
        case CHILD_TYPE_ELEMENT:
                return xml_enter_element((struct element *)child,
                                         (struct xml_closure *)closure);
        case CHILD_TYPE_TEXT:
                return xml_enter_text((struct text *)child,
                                      (struct xml_closure *)closure);
        default:
                abort();
        }
}

static int
xml_leave_element(struct element *element, struct xml_closure *closure)
{
        int r;
        assert(closure->indent.n > 0);
        closure->indent.n--;
        return (element->children.first != NULL &&
                ((closure->indent.s[closure->indent.n] &&
                  (r = indent(closure, closure->indent.n)) < 0) ||
                 (r = OUTS(closure, "</")) < 0 ||
                 (r = outname(closure, element->name)) < 0 ||
                 (r = OUTS(closure, ">")))) ||
                (closure->indent.s[closure->indent.n-1] &&
                 (r = OUTS(closure, "\n")) < 0) ? r : 0;
}

static int
xml_leave(struct child *child, void *closure)
{
        switch (child->type) {
        case CHILD_TYPE_ELEMENT:
                return xml_leave_element((struct element *)child,
                                         (struct xml_closure *)closure);
        case CHILD_TYPE_TEXT:
                return true;
        default:
                abort();
        }
}

static int
output_xml(struct io_out *out, struct parser *parser)
{
        struct xml_closure closure = {
                &parser->environment,
                RECSTACK_INIT(closure.indent),
                out,
        };
        int r;
        (r = OUTS(&closure,
                  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")) < 0 ||
                (r = child_traverse(&parser->top_level->self, xml_enter,
                                    xml_leave, &closure)) < 0 ||
                (r = OUTS(&closure, "\n"));
        bool_recstack_free(&closure.indent);
        return r;
}

static int lookup_keyword(YYSTYPE *value, const char *s, size_t n)
{
        for (int i = 3; i < 22; i++)
                if (yytname[i] != NULL && yytname[i][0] == '"' &&
                    memcmp(yytname[i] + 1, s, n) == 0 &&
                    yytname[i][n + 1] == '"' && yytname[i][n + 2] == '\0') {
                        value->keyword = (struct string){
                                &yytname[i][1], n, true
                        };
                        return 258 + (i - 3);
                }
        return 0;
}

void
rncc_debug(bool debug)
{
        _rncc_debug = debug;
}

int
rncc_parse(struct io_out *out, struct errors *errors, const char *s, size_t n)
{
        struct parser parser = {
                .p = s,
                .end = s + n,
                .l = { 1, 1, },
                .environment = { NULL, NULL, { { {0, 0}, {0, 0} }, inherit } },
                .top_level = NULL,
                .errors = errors,
                .realloc = realloc,
                .free = free,
        };
        int r;
        struct literal uri_xsd_literal = { NULL, uri_xsd, { {0, 0}, {0, 0} } };
        if (parser.p + 1 < parser.end &&
            (((unsigned char)parser.p[0] == 0xff &&
              (unsigned char)parser.p[1] == 0xfe) ||
             ((unsigned char)parser.p[0] == 0xfe &&
              (unsigned char)parser.p[1] == 0xff))) {
                parser_error_s(&parser,
                               &(struct location){ { 1, 1 }, { 1, 2 } },
                               "UTF-16 input isn’t supported");
                r = -EILSEQ;
        } else if (bind_prefix(&parser, (struct location){ {0, 0}, {0, 0} },
                               prefix_xml, &(struct location){ {0, 0}, {0, 0} },
                               uri_xml, &(struct location){ {0, 0}, {0, 0} }) &&
                   bind_datatype_prefix(&parser,
                                        (struct location){ {0, 0}, {0, 0} },
                                        prefix_xsd,
                                        (struct literals){
                                                &uri_xsd_literal,
                                                &uri_xsd_literal
                                        },
                                        &(struct location){ {0, 0}, {0, 0} }) &&
                   yyparse(&parser) == 0 && parser.errors->n == 0) {
                r = output_xml(out, &parser);
        } else
                r = -EILSEQ;
        element_free(&parser, parser.top_level);
        return r;
}
