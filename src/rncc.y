// TODO Replace abort() with error handling.
// TODO Add error reporting.
// TODO Free results.
// TODO Add tests.

// TODO Add proper output handling once libu is done.
// TODO Add proper input handling once libu is done.
%code requires {
#include <assert.h>
#include <errno.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct element;
struct parser;

#define lengthof(a) (sizeof(a) / sizeof((a)[0]))

#define list_for_each(type, item, list) \
        for (type *item = list; item != NULL; item = item->next)

#define list_for_each_safe(type, item, n, list) \
        for (type *item = list, *n = item != NULL ? item->next : NULL; item != NULL; item = n, n = n != NULL ? n->next : NULL)
}

%code
{
#define YYLTYPE struct location
#define YY_LOCATION_PRINT(File, Loc) location_print(File, Loc)
}

%union {
        struct string {
                const char *s;
                size_t n;
                bool shared;
        } string;
        struct string keyword;
        struct name {
                struct string uri;
                struct string local;
        } name;
        struct q_name {
                struct string prefix;
                struct string local;
        } q_name;
        struct attribute {
                struct attribute *next;
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
                /*
                struct context {
                        struct namespace_mapping *ns;
                        char *d; // TODO Is this needed?
                        // TODO Base URI?
                } context;
                */
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

// TODO Add %printers.

%destructor { string_free($$); } <string>
%destructor { name_free($$); } <name>
%destructor { string_free($$.prefix); string_free($$.local); } <q_name>
%destructor { attribute_free($$); } <attribute>
%destructor { attributes_free($$); } <attributes>
%destructor { content_free($$); } <content>
%destructor { element_free($$); } <element>
%destructor { elements_free($$); } <elements>
%destructor { attributes_free($$.attributes); content_free($$.content); } <xml>

%code
{
#if defined __GNUC__ && defined __GNUC_MINOR__
#  define U_GNUC_GEQ(major, minor) \
        ((__GNUC__ << 16) + __GNUC_MINOR__ >= ((major) << 16) + (minor))
#else
#  define U_GNUC_GEQ(major, minor) 0
#endif

#if U_GNUC_GEQ(2, 3)
#  define PRINTF(format_index, first_argument_index) \
        __attribute__((format(printf, format_index, first_argument_index)))
#  define UNUSED __attribute__((__unused__))
#else
#  define PRINTF(format_index, first_argument_index) /* PRINTF */
#  define UNUSED /* UNUSED */
#endif

static int PRINTF(2, 0)
formatv(char **output, const char *format, va_list args)
{
        va_list saved;
        va_copy(saved, args);
        char buf[1];
        int size = vsnprintf(buf, sizeof(buf), format, args);
        if (size < 0)
                return -EINVAL;
        char *result = malloc((size_t)size + 1);
        if (result == NULL)
                return -ENOMEM;
        if (vsnprintf(result, size + 1, format, saved) < 0) {
                free(result);
                return -EINVAL;
        }
        va_end(saved);
        *output = result;
        return size;
}

static int PRINTF(2, 3)
format(char **output, const char *format, ...)
{
        va_list args;
        va_start(args, format);
        int size = formatv(output, format, args);
        va_end(args);
        return size;
}

// TODO Change this.
struct location {
        int first_line;
        int last_line;
        int first_column;
        int last_column;
};

static int
location_str(char **s, const struct location *l)
{
        if (l->first_line == l->last_line) {
                if (l->first_column == l->last_column)
                        return format(s, "%d:%d",
                                      l->first_line, l->first_column);
                else
                        return format(s, "%d.%d-%d",
                                      l->first_line, l->first_column,
                                      l->last_column);
        } else
                return format(s, "%d.%d-%d.%d",
                              l->first_line, l->first_column,
                              l->last_line, l->last_column);
}

static unsigned int
location_print(FILE *out, const YYLTYPE location)
{
        char *s;
        int r = location_str(&s, &location);
        if (r < 0)
                return 0;
        r = fprintf(out, "%s", s);
        free(s);
        return (unsigned int)r;
}

struct error {
        struct error *next;
        struct location location;
        char *message;
};

static struct error oom_error = {
        NULL,
        { 0, 0, 0, 0 },
        (char *)(uintptr_t)"memory exhausted"
};

// TODO Check how location is usually passed
static struct error * PRINTF(2, 0)
error_newv(struct location *location, const char *message, va_list args)
{
        struct error *p = malloc(sizeof(*p));
        if (p == NULL)
                return NULL;
        *p = (struct error){ NULL, *location, NULL };
        if (formatv(&p->message, message, args) < 0) {
                free(p);
                return NULL;
        }
        return p;
}

// TODO Check how location is usually passed
UNUSED static struct error * PRINTF(2, 3)
error_new(struct location *location, const char *message, ...)
{
        va_list args;
        va_start(args, message);
        struct error *error = error_newv(location, message, args);
        va_end(args);
        return error;
}

static void
error_free(struct error *error)
{
        list_for_each_safe(struct error, p, n, error) {
                if (p != &oom_error) {
                        free(p->message);
                        free(p);
                }
        }
}

struct parser {
        const char *p;
        YYLTYPE location;
        struct environment {
                struct namespace_mapping {
                        struct namespace_mapping *next;
                        struct string prefix;
                        struct string uri;
                        bool used;
                } *ds;
                struct namespace_mapping *ns;
                struct string d;
                // TODO Base URI?
        } environment;
        struct element *top_level;
        struct {
                struct error *first;
                struct error *last;
        } errors;
};

static bool
parser_is_oom(struct parser *parser)
{
        return parser->errors.last == &oom_error;
}

static void
parser_errors(struct parser *parser, struct error *first, struct error *last)
{
        if (parser_is_oom(parser)) {
                error_free(first);
                return;
        }
        if (parser->errors.first == NULL)
                parser->errors.first = first;
        if (parser->errors.last != NULL)
                parser->errors.last->next = first;
        if (last != NULL)
                parser->errors.last = last;
}

static void
parser_oom(struct parser *parser)
{
        if (parser_is_oom(parser))
                return;
        oom_error.location = parser->location;
        parser_errors(parser, &oom_error, &oom_error);
}

static bool PRINTF(3, 0)
parser_errorv(struct parser *parser, YYLTYPE *location,
              const char *message, va_list args)
{
        if (parser_is_oom(parser))
                return false;
        struct error *error = error_newv(location, message, args);
        if (error == NULL) {
                parser_oom(parser);
                return false;
        }
        parser_errors(parser, error, error);
        return true;
}

static bool PRINTF(3, 4)
parser_error(struct parser *parser, YYLTYPE *location,
             const char *message, ...)
{
        va_list args;
        va_start(args, message);
        bool r = parser_errorv(parser, location, message, args);
        va_end(args);
        return r;
}

static char _inherit;
static const struct string inherit = { &_inherit, 0, true };

#undef STRING
#define STRING(s) (struct string){ s, sizeof(s) - 1, true }

static const struct string uri_rng =
        STRING("http://relaxng.org/ns/structure/1.0");

static const struct string prefix_xml = STRING("xml");
static const struct string uri_xml =
        STRING("http://www.w3.org/XML/1998/namespace");

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
string_free(struct string s)
{
        if (!s.shared)
                free((char *)(uintptr_t)s.s);
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
name_free(struct name name)
{
        string_free(name.uri);
        string_free(name.local);
}

static struct attribute *
attribute(struct name name, struct string value)
{
        struct attribute *p = malloc(sizeof(*p));
        if (p == NULL)
                return NULL;
        *p = (struct attribute){ NULL, name, value };
        return p;
}

static struct attributes
attribute_to_attributes(struct attribute *attribute)
{
        assert(attribute == NULL || attribute->next == NULL);
        return (struct attributes){ attribute, attribute };
}

static void
attribute_free(struct attribute *attribute)
{
        if (attribute == NULL)
                return;
        name_free(attribute->name);
        string_free(attribute->value);
        free(attribute);
}

static struct attributes
attributes_concat(struct attributes left, struct attributes right)
{
        if (left.first == NULL) {
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

static struct xml
attributes_to_xml(struct attributes attributes)
{
        return (struct xml){ attributes, { NULL, NULL } };
}

static void
attributes_free(struct attributes attributes)
{
        list_for_each_safe(struct attribute, p, n, attributes.first)
                attribute_free(p);
}

static struct content
content_concat(struct content left, struct content right)
{
        if (left.first == NULL) {
                assert(left.last == NULL);
                left.first = right.first;
        } else
                left.last->next = right.first;
        return (struct content){ left.first, right.last };
}

static void element_free(struct element *element);
static void text_free(struct text *text);

static struct content
content_empty(void)
{
        return (struct content){ NULL, NULL };
}

static void
content_free(struct content content)
{
        list_for_each_safe(struct child, p, n, content.first)
                if (p->type == CHILD_TYPE_ELEMENT)
                        element_free((struct element *)p);
                else
                        text_free((struct text *)p);
}

static struct element *
element(struct name name, struct xml xml)
{
        struct element *p = malloc(sizeof(*p));
        if (p == NULL)
                return NULL;
        *p = (struct element){
                { NULL, CHILD_TYPE_ELEMENT }, name, xml.attributes, xml.content
        };
        return p;
}

static struct element *
rng_element(struct string x, struct xml y)
{
        return element(NAME(uri_rng, x), y);
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
element_free(struct element *element)
{
        if (element == NULL)
                return;
        name_free(element->name);
        attributes_free(element->attributes);
        content_free(element->children);
        free(element);
}

static struct elements
elements_empty(void)
{
        return element_to_elements(NULL);
}

static struct elements
elements_concat(struct elements left, struct elements right)
{
        if (left.first == NULL) {
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
elements_free(struct elements elements)
{
        content_free(elements_to_content(elements));
}

static struct content
text(struct string s)
{
        struct text *p = malloc(sizeof(*p));
        if (p == NULL)
                return (struct content){ NULL, NULL };
        *p = (struct text){ { NULL, CHILD_TYPE_TEXT }, s };
        return (struct content){ &p->self, &p->self };
}

static void
text_free(struct text *text)
{
        if (text == NULL)
                return;
        string_free(text->string);
        free(text);
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

static void
mark_prefix_used(struct environment *environment, struct string prefix)
{
        for (struct namespace_mapping *p = environment->ns; p != NULL; p = p->next)
                if (string_cmp(p->prefix, prefix) == 0) {
                        p->used = true;
                        return;
                }
        abort();
}

static struct string
lookup_prefix(struct environment *environment, struct string prefix)
{
        for (struct namespace_mapping *p = environment->ns; p != NULL; p = p->next)
                if (string_cmp(p->prefix, prefix) == 0)
                        return p->uri;
        abort();
}

static struct string
lookup_default(struct environment *environment)
{
        return environment->d;
}

static struct string
lookup_datatype_prefix(struct environment *environment, struct string prefix)
{
        for (struct namespace_mapping *p = environment->ds; p != NULL; p = p->next)
                if (string_cmp(p->prefix, prefix) == 0)
                        return p->uri;
        abort();
}

static struct namespace_mapping *
bind_prefix(struct environment *environment, struct string prefix,
            struct string uri)
{
        if (string_cmp(prefix, prefix_xml) == 0 && string_cmp(uri, uri_xml) != 0)
                abort();
        if (string_cmp(uri, uri_xml) == 0 && string_cmp(prefix, prefix_xml) != 0)
                abort();
        for (struct namespace_mapping *p = environment->ns; p != NULL; p = p->next)
                if (string_cmp(p->prefix, prefix) == 0) {
                        if (string_cmp(prefix, prefix_xml) == 0)
                                return p;
                        else
                                abort();
                }
        struct namespace_mapping *p = malloc(sizeof(*p));
        if (p == NULL)
                return NULL;
        *p = (struct namespace_mapping){ environment->ns, prefix, uri, false };
        environment->ns = p;
        return p;
}

static void
bind_default(struct environment *environment, struct string uri)
{
        if (string_cmp(uri, uri_xml) == 0)
                abort();
        if (string_is_inherit(uri))
                abort();
        environment->d = uri;
}

static struct namespace_mapping *
bind_datatype_prefix(struct environment *environment, struct string prefix,
                     struct string uri)
{
        if (string_cmp(prefix, prefix_xsd) == 0 && string_cmp(uri, uri_xsd) != 0)
                abort();
        // TODO We must verify that uri isn’t relative.
        // TODO We must verify that uri doesn’t have a fragment identifier.
        for (struct namespace_mapping *p = environment->ns; p != NULL; p = p->next)
                if (string_cmp(p->prefix, prefix) == 0) {
                        if (string_cmp(prefix, prefix_xsd) == 0)
                                return p;
                        else
                                abort();
                }
        struct namespace_mapping *p = malloc(sizeof(*p));
        if (p == NULL)
                return NULL;
        *p = (struct namespace_mapping){ environment->ds, prefix, uri, false };
        environment->ds = p;
        return p;
}

static struct string
map_schema_ref(UNUSED struct environment *environment, struct string uri)
{
        return uri;
}

static bool
make_ns_attribute(struct attributes *attributes, struct string uri)
{
        if (string_is_inherit(uri))
                return *attributes = empty().attributes, true;
        *attributes = attribute_to_attributes(attribute(LNAME("name"), uri));
        return attributes->first != NULL;
}

static struct element *
apply_annotations(struct xml xml, struct element *element)
{
        element->attributes = attributes_concat(xml.attributes,
                                                element->attributes);
        element->children = content_concat(xml.content, element->children);
        return element;
}

static struct elements
apply_annotations_group(struct xml xml, struct elements elements)
{
        if (xml.attributes.first == NULL && xml.content.first == NULL) {
                assert(xml.attributes.last == NULL);
                assert(xml.content.last == NULL);
                return elements;
        }
        struct element *e = rng_element(STRING("group"),
                                        elements_to_xml(elements));
        if (e == NULL)
                return elements_empty();
        return element_to_elements(apply_annotations(xml, e));
}

static struct elements
apply_annotations_choice(struct xml xml, struct elements elements)
{
        if (xml.attributes.first == NULL && xml.content.first == NULL) {
                assert(xml.attributes.last == NULL);
                assert(xml.content.last == NULL);
                return elements;
        }
        struct element *e = rng_element(STRING("choice"),
                                        elements_to_xml(elements));
        if (e == NULL)
                return elements_empty();
        return element_to_elements(apply_annotations(xml, e));
}

static struct attributes
datatype_attributes(struct string library, struct string type)
{
        struct attribute *l = attribute(LNAME("datatypeLibrary"), library);
        struct attribute *t = NULL;
        if (l != NULL) {
                t = attribute(LNAME("type"), type);
                l->next = t;
                if (t == NULL) {
                        free(l);
                        l = NULL;
                }
        }
        return (struct attributes){ l, t };
}

static struct element *
rng_element_with_attribute(struct string element_name,
                           struct string attribute_name, struct string value,
                           struct attributes attributes,
                           struct content content)
{
        struct attribute *a = attribute(NAME(STRING(""), attribute_name), value);
        if (a == NULL)
                return NULL;
        struct element *e = rng_element(element_name, (struct xml) {
                                                attributes_cons(a, attributes),
                                                content });
        if (e == NULL)
                free(a);
        return e;
}

static struct element *
rng_element_with_element(struct string parent_name,
                         struct attributes attributes,
                         struct elements parent_elements,
                         struct string child_name,
                         struct elements child_elements)
{
        struct element *c = rng_element(child_name,
                                        elements_to_xml(child_elements));
        if (c == NULL)
                return NULL;
        struct element *p = rng_element(parent_name,
                                        attributes_and_elements_to_xml(
                                                attributes,
                                                elements_append(parent_elements,
                                                                c)));
        if (p == NULL)
                free(c);
        return p;
}

static struct element *
rng_element_with_text(struct string name, struct attributes attributes,
                      struct string string)
{
        struct content c = text(string);
        if (c.first == NULL)
                return NULL;
        struct element *e = rng_element(name, (struct xml){ attributes, c});
        if (e == NULL)
                content_free(c);
        return e;
}

static struct element *
ns_name_element(struct environment *environment, struct string prefix,
                struct elements elements)
{
        struct attributes ns;
        struct element *e = NULL;
        if (make_ns_attribute(&ns, lookup_prefix(environment, prefix)) &&
            (e = rng_element(STRING("nsName"),
                             attributes_and_elements_to_xml(ns,
                                                            elements))) == NULL)
                attributes_free(ns);
        return e;
}

static struct element *
ns_name_except_element(struct environment *environment, struct string prefix,
                       struct elements elements)
{
        struct element *ex, *e = NULL;
        if ((ex = rng_element(STRING("except"),
                              elements_to_xml(elements))) != NULL &&
            (e = ns_name_element(environment, prefix,
                                 element_to_elements(ex))) == NULL)
                free(ex);
        return e;
}

static struct element *
name_element(struct string uri, struct string name)
{
        struct attributes ns;
        struct content c = content_empty();
        struct element *e = NULL;
        if (make_ns_attribute(&ns, uri) &&
            ((c = text(name)).first == NULL ||
             (e = rng_element(STRING("name"), (struct xml){
                             ns, c })) == NULL)) {
                content_free(c);
                attributes_free(ns);
        }
        return e;
}

static int yylex(YYSTYPE *value, YYLTYPE *location, struct parser *parser);

static void
yyerror(YYLTYPE *location, struct parser *parser, const char *message)
{
        parser_error(parser, location, "%s", message);
}
}

%define api.pure full
%parse-param {struct parser *parser}
%lex-param {struct parser *parser}
%token-table
%debug
%define parse.error verbose
%expect 0
%locations

%token
  END 0 "end of file"
  ERROR
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
  <string> DOCUMENTATION
  <q_name> C_NAME
  <string> NS_NAME
  <string> LITERAL
  <string> IDENTIFIER
;

%type <attribute> annotation_attribute nested_annotation_attribute
%type <attributes> assign_op opt_inherit datatype_name annotation_attributes
%type <attributes> nested_annotation_attributes
%type <content> param_value annotation_content documentation
%type <element> top_level_body member annotated_component component
%type <element> start define include include_member annotated_include_component
%type <element> include_component div include_div repeated_primary
%type <element> lead_annotated_data_except primary data_except annotated_param
%type <element> param except_element_name_class except_attribute_name_class
%type <element> simple_element_name_class simple_attribute_name_class
%type <element> simple_name_class annotation_element
%type <element> annotation_element_not_keyword nested_annotation_element
%type <elements> grammar opt_include_body include_body pattern top_level_pattern
%type <elements> inner_pattern top_level_inner_pattern particle_choice
%type <elements> particle_group particle_interleave particle inner_particle
%type <elements> top_level_inner_particle annotated_primary
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
%type <string> datatype_value identifier_or_keyword literal
%type <string> identifier
%type <xml> nested_annotation_attributes_and_annotation_content
%type <xml> annotation_attributes_and_elements
%type <xml> annotations annotation_attributes_content

%code
{
#define B(p) do { if (!(p)) { parser_oom(parser); YYABORT; } } while (0)
#define M(p) B((p) != NULL)
#define L(p) M((p).last)
#define S(p) M((p).s)

// TODO Configure check for this.
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wconversion"
}

%%

top_level: preamble top_level_body { parser->top_level = $2; };

preamble:
  %empty
| decl preamble;

decl:
  "namespace" namespace_prefix '=' namespace_uri_literal
    { M(bind_prefix(&parser->environment, $2, $4)); }
| "default" "namespace" '=' namespace_uri_literal
    { bind_default(&parser->environment, $4); }
| "default" "namespace" namespace_prefix '=' namespace_uri_literal
    { M(bind_prefix(&parser->environment, $3, $5));
      bind_default(&parser->environment, $5); }
| "datatypes" datatype_prefix '=' literal
    { M(bind_datatype_prefix(&parser->environment, $2, $4)); }

namespace_prefix:
  identifier_or_keyword
    { if (string_cmp($1, STRING("xmlns")) == 0)
              abort();
      $$ = $1; }

datatype_prefix: identifier_or_keyword;

namespace_uri_literal: literal | "inherit" { $$ = inherit; };

top_level_body:
  %empty
    { M($$ = rng_element(STRING("grammar"), empty())); }
| grammar
    { M($$ = rng_element(STRING("grammar"), elements_to_xml($1))); }
| top_level_pattern
    { if ($1.last != $1.first)
              abort();
      $$ = $1.first; }

grammar:
  member { $$ = element_to_elements($1); }
| grammar member { $$ = elements_append($1, $2); };

member: annotated_component
| annotation_element_not_keyword;

annotated_component: annotations component { $$ = apply_annotations($1, $2); };

component: start
| define
| include
| div;

start:
  "start" assign_op pattern
    { M($$ = rng_element($1, attributes_and_elements_to_xml($2, $3)));};

define:
  identifier assign_op pattern
    { M($$ = rng_element_with_attribute(STRING("define"), STRING("name"), $1, $2,
                                        elements_to_content($3))); }

assign_op:
  '='
    { $$ = empty().attributes; }
| "|="
    { L($$ = attribute_to_attributes(attribute(LNAME("combine"),
                                               STRING("choice")))); }
| "&="
    { L($$ = attribute_to_attributes(attribute(LNAME("combine"),
                                               STRING("interleave")))); };

include:
  "include" any_uri_literal opt_inherit opt_include_body
    { M($$ = rng_element_with_attribute($1, STRING("href"),
                                        map_schema_ref(&parser->environment, $2),
                                        $3, elements_to_content($4))); };

any_uri_literal: literal { /* TODO Verify anyURI */ $$ = $1; };

opt_inherit:
  %empty
    { B(make_ns_attribute(&$$, lookup_default(&parser->environment))); }
| "inherit" '=' identifier_or_keyword
    { B(make_ns_attribute(&$$, lookup_prefix(&parser->environment, $3))); };

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

div: "div" '{' grammar '}' { M($$ = rng_element($1, elements_to_xml($3))); };

include_div:
  "div" '{' include_body '}' { M($$ = rng_element($1, elements_to_xml($3))); };

pattern: inner_pattern;

top_level_pattern: top_level_inner_pattern;

inner_pattern:
  inner_particle
| particle_choice
    { L($$ = element_to_elements(rng_element(STRING("choice"),
                                             elements_to_xml($1)))); }
| particle_group
    { L($$ = element_to_elements(rng_element(STRING("group"),
                                             elements_to_xml($1)))); }
| particle_interleave
    { L($$ = element_to_elements(rng_element(STRING("interleave"),
                                             elements_to_xml($1)))); }
| annotated_data_except;

top_level_inner_pattern:
  top_level_inner_particle
| particle_choice
| particle_group
| particle_interleave
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
    { M($$ = rng_element(STRING("zeroOrMore"), elements_to_xml($1))); }
| annotated_primary '+'
    { M($$ = rng_element(STRING("oneOrMore"), elements_to_xml($1))); }
| annotated_primary '?'
    { M($$ = rng_element(STRING("optional"), elements_to_xml($1))); };

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
                      apply_annotations_group($1, $3)); };

primary:
  "element" element_name_class '{' pattern '}'
    { M($$ = rng_element($1, elements_to_xml(elements_concat($2, $4)))); }
| "attribute" attribute_name_class '{' pattern '}'
    { M($$ = rng_element($1, elements_to_xml(elements_concat($2, $4)))); }
| "mixed" '{' pattern '}'
    { M($$ = rng_element($1, elements_to_xml($3))); }
| "list" '{' pattern '}'
    { M($$ = rng_element($1, elements_to_xml($3))); }
| datatype_name opt_params
    { M($$ = rng_element(STRING("data"),
                         attributes_and_elements_to_xml($1, $2))); }
| datatype_name datatype_value
    { M($$ = rng_element_with_text(STRING("value"), $1, $2)); }
| datatype_value
    { M($$ = rng_element_with_text(STRING("value"), empty().attributes, $1)); }
| "empty"
    { M($$ = rng_element($1, empty())); }
| "notAllowed"
    { M($$ = rng_element($1, empty())); }
| "text"
    { M($$ = rng_element($1, empty())); }
| ref
    { M($$ = rng_element_with_attribute(STRING("ref"), STRING("name"), $1,
                                        empty().attributes, content_empty())); }
| "parent" ref
    { M($$ = rng_element_with_attribute(STRING("parentRef"), STRING("name"), $2,
                                        empty().attributes, content_empty())); }
| "grammar" '{' grammar '}'
    { M($$ = rng_element($1, elements_to_xml($3))); }
| "external" any_uri_literal opt_inherit
    { M($$ = rng_element_with_attribute(STRING("externalRef"), STRING("href"),
                                        map_schema_ref(&parser->environment, $2),
                                        $3, content_empty())); };

data_except:
  datatype_name opt_params '-' lead_annotated_primary
  { M($$ = rng_element_with_element(STRING("data"), $1, $2, STRING("except"),
                                    $4)); };

ref: identifier;

datatype_name:
  c_name
    { L($$ = datatype_attributes(lookup_datatype_prefix(&parser->environment,
                                                        $1.prefix),
                                 $1.local)); }
| "string"
    { L($$ = datatype_attributes(STRING(""), $1)); }
| "token"
    { L($$ = datatype_attributes(STRING(""), $1)); };

datatype_value: literal;

opt_params:
  %empty { $$ = elements_empty(); }
| '{' params '}' { $$ = $2; };

params:
  %empty { $$ = elements_empty(); }
| params annotated_param { $$ = elements_append($1, $2); };

annotated_param: annotations param { $$ = apply_annotations($1, $2); };

param:
  identifier_or_keyword '=' param_value
    { M($$ = rng_element_with_attribute(STRING("param"),
                                        STRING("name"), $1,
                                        empty().attributes, $3)); };

param_value: literal { L($$ = text($1)); };

element_name_class:
  annotated_simple_element_name_class
| element_name_class_choice
    { L($$ = element_to_elements(rng_element(STRING("choice"),
                                             elements_to_xml($1)))); }
| annotations except_element_name_class follow_annotations
    { $$ = elements_cons(apply_annotations($1, $2), $3); };

attribute_name_class:
  annotated_simple_attribute_name_class
| attribute_name_class_choice
    { L($$ = element_to_elements(rng_element(STRING("choice"),
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
                      apply_annotations_choice($1, $3)); };

lead_annotated_simple_attribute_name_class:
  annotations simple_attribute_name_class
    { $$ = element_to_elements(apply_annotations($1, $2)); }
| annotations '(' attribute_name_class ')'
    { L($$ = name_cmp($3.first->name, NAME(uri_rng, STRING("choice"))) == 0 ?
                      element_to_elements(apply_annotations($1, $3.first)) :
                      apply_annotations_choice($1, $3)); };

except_element_name_class:
  NS_NAME '-' lead_annotated_simple_element_name_class
  { $$ = ns_name_except_element(&parser->environment, $1, $3); }
| '*' '-' lead_annotated_simple_element_name_class
    { M($$ = rng_element_with_element(STRING("anyName"), empty().attributes,
                                      elements_empty(), STRING("except"),
                                      $3)); };

except_attribute_name_class:
  NS_NAME '-' lead_annotated_simple_attribute_name_class
    { M($$ = ns_name_except_element(&parser->environment, $1, $3)); }
| '*' '-' lead_annotated_simple_attribute_name_class
    { M($$ = rng_element_with_element(STRING("anyName"), empty().attributes,
                                      elements_empty(), STRING("except"),
                                      $3)); };

simple_element_name_class:
  identifier_or_keyword
    { M($$ = name_element(lookup_default(&parser->environment), $1)); }
| simple_name_class;

simple_attribute_name_class:
  identifier_or_keyword { M($$ = name_element(STRING(""), $1)); }
| simple_name_class;

simple_name_class:
  c_name
    { mark_prefix_used(&parser->environment, $1.prefix);
            M($$ = name_element(lookup_prefix(&parser->environment, $1.prefix),
                                $1.local)); }
| NS_NAME
    { M($$ = ns_name_element(&parser->environment, $1, elements_empty())); }
| '*'
    { M($$ = rng_element(STRING("anyName"), empty())); };

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
  // TODO Check $1 for duplicates.
    { $$ = attributes_to_xml($1); }
| annotation_attributes annotation_elements
  // TODO Check $1 for duplicates.
    { $$ = attributes_and_elements_to_xml($1, $2); }
| annotation_elements
    { $$ = elements_to_xml($1); };

annotation_attributes:
  annotation_attribute { $$ = attribute_to_attributes($1); }
| annotation_attributes annotation_attribute { $$ = attributes_append($1, $2); };

annotation_attribute:
  foreign_attribute_name '=' literal { M($$ = attribute($1, $3)); };

foreign_attribute_name:
  prefixed_name
    { if (string_cmp($1.uri, uri_xmlns) == 0)
              abort();
      if (string_cmp($1.uri, STRING("")) == 0)
              abort();
      if (string_cmp($1.uri, uri_rng) == 0)
              abort();
      $$ = $1; };

annotation_elements:
  annotation_element { $$ = element_to_elements($1); }
| annotation_elements annotation_element { $$ = elements_append($1, $2); };

annotation_element:
  foreign_element_name annotation_attributes_content { $$ = element($1, $2); };

foreign_element_name:
  identifier_or_keyword
    { $$ = name(STRING(""), $1); }
| prefixed_name
    { if (string_cmp($1.uri, uri_rng) == 0)
              abort();
      $$ = $1; };

/* To avoid shift/reduce, we add annotations here and then generate a
 * syntax error if it isn’t empty. */
annotation_element_not_keyword:
  annotations foreign_element_name_not_keyword annotation_attributes_content
    { if ($1.attributes.first != NULL || $1.content.first != NULL)
                    abort();
      assert($1.attributes.last == NULL);
      assert($1.content.last == NULL);
      M($$ = element($2, $3)); };

foreign_element_name_not_keyword:
  identifier
    { $$ = name(STRING(""), $1); }
| prefixed_name
    { if (string_cmp($1.uri, uri_rng) == 0)
              abort();
      $$ = $1; };

annotation_attributes_content:
  '[' nested_annotation_attributes_and_annotation_content ']' { $$ = $2; };

nested_annotation_attributes_and_annotation_content:
  %empty
    { $$ = empty(); }
| nested_annotation_attributes
  // TODO Check $1 for duplicates.
    { $$ = attributes_to_xml($1); }
| nested_annotation_attributes annotation_content
  // TODO Check $1 for duplicates.
    { $$ = (struct xml){ $1, $2 }; }
| annotation_content
    { $$ = (struct xml){ empty().attributes, $1 }; };

nested_annotation_attributes:
  nested_annotation_attribute
    { $$ = attribute_to_attributes($1); }
| nested_annotation_attributes nested_annotation_attribute
    { $$ = attributes_append($1, $2); };

nested_annotation_attribute:
  any_attribute_name '=' literal { M($$ = attribute($1, $3)); };

any_attribute_name:
  identifier_or_keyword
    { $$ = name(STRING(""), $1); }
| prefixed_name
    { if (string_cmp($1.uri, uri_xmlns) == 0)
              abort();
      $$ = $1; };

annotation_content:
  annotation_element
    { $$ = element_to_xml($1).content; }
| literal
    { L($$ = text($1)); }
| annotation_content nested_annotation_element
    { $$ = content_concat($1, element_to_xml($2).content); }
| annotation_content literal
    { L($$ = content_concat($1, text($2))); };

nested_annotation_element:
  any_element_name annotation_attributes_content
    { M($$ = element($1, $2)); };

any_element_name:
  identifier_or_keyword { $$ = name(STRING(""), $1); }
| prefixed_name;

prefixed_name:
  c_name
    { if (string_is_inherit($1.prefix))
              abort();
      mark_prefix_used(&parser->environment, $1.prefix);
      $$ = name(lookup_prefix(&parser->environment, $1.prefix), $1.local); };

documentations:
  %empty
    { $$ = elements_empty(); }
| documentations documentation
    { L($$ = elements_append($1,
                             element(name_documentation,
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

literal: LITERAL { S($$ = $1); }
/*literal: literal_segment
| literal_segment '~' literal;
*/

identifier: IDENTIFIER { S($$ = $1); }

c_name: C_NAME { $$ = $1; S($$.prefix); S($$.local); }

documentation: DOCUMENTATION { S($1); L($$ = text($1)); }

%%

#pragma GCC diagnostic pop

static bool
xml_is_nc_name_start_char(unsigned int c)
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
xml_is_nc_name_char(unsigned int c)
{
        return xml_is_nc_name_start_char(c) ||
                c == '-' ||
                c == '.' ||
                ('0' <= c && '9' <= c) ||
                c == 0xb7 ||
                (0x300 <= c && c <= 0x36f) ||
                (0x203f <= c && c <= 0x2040);
}

static void
locate(struct parser *parser, YYLTYPE *location, const char *p, const char *q)
{
        // TODO Use u_width.
        if (q - p > 0)
                parser->location.last_column += q - p; // TODO - 1?
        *location = parser->location;
}

static int
yylex_token(struct parser *parser, YYLTYPE *location, const char *q, int token)
{
        locate(parser, location, parser->p, q);
        parser->p = q;
        return token;
}

static int
yylex_string(struct parser *parser, YYLTYPE *location, YYSTYPE *value,
             const char *p,
             const char *q, const char *end, int token)
{
        value->string = (struct string){ p, (size_t)(q - p), true };
        return yylex_token(parser, location, end, token);
}

/* TODO Handle separator. */
/* TODO Handle """ and '''. */
/* TODO Handle \x{…}. */
/* TODO Handle Char. */
/* TODO Handle normalization. */
/* TODO Handle newline. */
static int
yylex(YYSTYPE *value, YYLTYPE *location, struct parser *parser)
{
        while (true) {
                if (*parser->p == '\n') {
                        parser->location.last_line =
                                parser->location.first_line++;
                        parser->location.first_column = 1;
                        parser->location.last_column = 0;
                } else if (*parser->p != ' ')
                        break;
                parser->p++;
                parser->location.last_column++;
        }
        if (*parser->p == '\0')
                return yylex_token(parser, location, parser->p, END);
        const char *q = parser->p;
        if ((0x1 <= *q && *q <= 0x8) ||
            (0xb <= *q && *q <= 0xc) ||
            (0xe <= *q && *q <= 0x1f) ||
            (0xd800 <= (unsigned int)*q && (unsigned int)*q <= 0xdfff))
                // TODO Generate error.
                return yylex_token(parser, location, q + 1, ERROR);
        else if (*q == '"') {
                q++;
                // TODO Is this right? Not break on newline?
                while (*q != '\0' && *q != '"')
                        q++;
                if (*q == '\0') {
                        // TODO Generate error.
                        return yylex_token(parser, location, q, ERROR);
                }
                return yylex_string(parser, location, value, parser->p + 1,
                                    q, q + 1, LITERAL);
        } else if (*q == '=' || *q == '{' || *q == '}' || *q == '(' ||
                   *q == ')' || *q == '[' || *q == ']' || *q == '+' ||
                   *q == '?' || *q == '*' || *q == '-' || *q == ',')
                return yylex_token(parser, location, q + 1, *q);
        else if (*q == '&')
                return q[1] == '=' ?
                        yylex_token(parser, location, q + 2, COMBINE_INTERLEAVE):
                        yylex_token(parser, location, q + 1, *q);
        else if (*q == '|')
                return q[1] == '=' ?
                        yylex_token(parser, location, q + 2, COMBINE_CHOICE):
                        yylex_token(parser, location, q + 1, *q);
        else if (*q == '>' && q[1] == '>')
                return yylex_token(parser, location, q + 2, FOLLOW_ANNOTATION);
        bool escaped = *q == '\\';
        if (escaped)
                q++;
        if (!xml_is_nc_name_start_char((unsigned int)*q))
                /* TODO Error */
                return yylex_token(parser, location, q, ERROR);
        q++;
        while (xml_is_nc_name_char((unsigned int)*q))
                q++;
        if (!escaped)
                for (size_t i = 3, n = (size_t)(q - parser->p); i < YYNTOKENS; i++)
                        if (yytname[i] != NULL && yytname[i][0] == '"' &&
                            strncmp(yytname[i] + 1, parser->p, n) == 0&&
                            yytname[i][n + 1] == '"' &&
                            yytname[i][n + 2] == '\0') {
                                value->keyword = (struct string){
                                        &yytname[i][1], n, true
                                };
                                locate(parser, location, parser->p, q);
                                parser->p = q;
                                return 258 + ((int)i - 3);
                        }
        // TODO Should this be checked before !escaped above?
        if (*q == ':') {
                q++;
                if (*q == '*')
                        return yylex_string(parser, location, value, parser->p,
                                            q - 1, q + 1, NS_NAME);
                else {
                        value->q_name.prefix = (struct string){
                                parser->p, (size_t)(q - 1 - parser->p), true
                        };
                        const char *p = q;
                        while (xml_is_nc_name_char((unsigned int)*q))
                                q++;
                        value->q_name.local = (struct string){
                                p, (size_t)(q - p), true
                        };
                        locate(parser, location, parser->p, q);
                        parser->p = q;
                        return C_NAME;
                }
        } else
                return yylex_string(parser, location, value, parser->p, q, q,
                                    IDENTIFIER);
}

/* Output */
struct action {
        struct action *next;
        bool enter;
        struct child *children;
};

static bool
push(struct action **actions, struct action **used, bool enter,
     struct child *children)
{
        struct action *p;
        if (*used != NULL) {
                p = *used;
                *used = (*used)->next;
        } else {
                p = malloc(sizeof(*p));
                if (p == NULL)
                        abort();
        }
        p->next = *actions;
        p->enter = enter;
        p->children = children;
        *actions = p;
        return true;
}

static void
pop(struct action **actions, struct action **used)
{
        struct action *p = *actions;
        *actions = (*actions)->next;
        p->next = *used;
        *used = p;
}

static bool
child_traverse(struct child *child, bool (*enter)(struct child *, void *),
               bool (*leave)(struct child *, void *), void *closure)
{
        if (child == NULL)
                return true;
        bool done = false;
        struct action *actions = NULL;
        struct action *used = NULL;
        if (!push(&actions, &used, true, child))
                goto oom;
        while (actions != NULL) {
                if (actions->enter) {
                        struct child *p = actions->children;
                        actions->children = p->next;
                        if (actions->children == NULL)
                                pop(&actions, &used);
                        if (!enter(p, closure))
                                goto exit;
                        if (!push(&actions, &used, false, p) ||
                            (p->type == CHILD_TYPE_ELEMENT &&
                             ((struct element *)p)->children.first != NULL &&
                             !push(&actions, &used, true,
                                   ((struct element *)p)->children.first)))
                                goto exit;
                } else {
                        if (!leave(actions->children, closure))
                                goto exit;
                        pop(&actions, &used);
                }
        }
        done = true;
        goto exit;
oom:
        abort();
exit:
        list_for_each_safe(struct action, p, n, actions)
                free(p);
        list_for_each_safe(struct action, p, n, used)
                free(p);
        return done;
}

struct xml_closure {
        struct environment *environment;
        size_t indent;
};

static bool
outs(UNUSED struct xml_closure *closure, const char *string, size_t length)
{
        fwrite(string, sizeof(char), length, stdout);
        return true;
}

static bool
outc(struct xml_closure *closure, char c)
{
        return outs(closure, &c, 1);
}

static bool
outname(struct xml_closure *closure, struct name name)
{
        struct namespace_mapping *p = NULL;
        if (name.uri.n > 0) {
                for (p = closure->environment->ns; p != NULL; p = p->next) {
                        if (string_cmp(p->uri, name.uri) == 0)
                                break;
                }
                if (p == NULL)
                        assert(string_cmp(name.uri,
                                          closure->environment->d) == 0 ||
                               string_cmp(name.uri,
                                          uri_rng) == 0);
        }
        if (!((p == NULL ||
               p->prefix.n == 0 ||
               (outc(closure, ':') &&
                outs(closure, p->prefix.s, p->prefix.n))) &&
              outs(closure, name.local.s, name.local.n)))
                abort();
        return true;
}

static bool
indent(struct xml_closure *closure, size_t n)
{
        if (!outc(closure, '\n'))
                return false;
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
        while (n > 0) {
                size_t i = n < lengthof(cs) / 2 ? n : lengthof(cs) / 2;
                if (!outs(closure, cs, 2 * i))
                        return false;
                n -= i;
        }
        return true;
}

struct entity {
        const char *s;
        size_t n;
};

#define E(s) { s, sizeof(s) - 1 }
#define N { NULL, 0 }
static const struct entity text_entities[] = {
        N,N,N,N,N,N,N,N,N,N,N,N,N,N,N,N,
        N,N,N,N,N,N,N,N,N,N,N,N,N,N,N,N,
        N,N,N,N,N,N,E("&amp;"),N,N,N,N,N,N,N,N,N,
        N,N,N,N,N,N,N,N,N,N,N,N,E("&lt;")
};

static const struct entity attribute_entities[] = {
        N,N,N,N,N,N,N,N,N,E("&#9;"),E("&#10;"),N,N,E("&#13;"),N,N,
        N,N,N,N,N,N,N,N,N,N,N,N,N,N,N,N,
        N,N,E("&quot;"),N,N,N,E("&amp;"),N,N,N,N,N,N,N,N,N,
        N,N,N,N,N,N,N,N,N,N,N,N,E("&lt;"),N,E("&gt;")
};
#undef N
#undef E

static bool
escape(struct xml_closure *closure, struct string string,
       const struct entity *entities, size_t n_entities)
{
        const char *p = string.s, *q = p, *end = q + string.n;
        // TODO Handle escaping of ]]>.
        while (q < end) {
                const struct entity *e;
                if ((unsigned char)*q < n_entities &&
                    (e = &entities[(unsigned char)*q])->n > 0) {
                        if (!(outs(closure, p, (size_t)(q - p)) &&
                              outs(closure, e->s, e->n)))
                                return false;
                        p = q + 1;
                }
                q++;
        }
        return outs(closure, p, (size_t)(q - p));
}

static bool
is_indent(struct element *element)
{
        for (struct child *p = element->children.first; p != NULL; p = p->next)
                if (p->type == CHILD_TYPE_TEXT)
                        return false;
        return element->children.first != NULL;
}

static bool
outnamespace(struct xml_closure *closure, struct namespace_mapping *p)
{
        if (!(outs(closure, " xmlns:", 7) &&
              outs(closure, p->prefix.s, p->prefix.n) &&
              outs(closure, "=\"", 2) &&
              escape(closure, p->uri,
                     attribute_entities,
                     lengthof(attribute_entities)) &&
              outc(closure, '"')))
                abort();
        return true;
}

static bool
xml_enter_element(struct element *element, struct xml_closure *closure)
{
        if (!outc(closure, '<'))
                abort();
        if (!outname(closure, element->name))
                abort();
        if (closure->indent == 0) {
                if (!(outs(closure, " xmlns=\"", 8) &&
                      escape(closure, element->name.uri, attribute_entities,
                             lengthof(attribute_entities)) &&
                      outc(closure, '"')))
                        abort();
                for (struct namespace_mapping *p = closure->environment->ns;
                     p != NULL; p = p->next)
                        if (p->used)
                                outnamespace(closure, p);
        }
        for (struct attribute *p = element->attributes.first; p != NULL;
             p = p->next) {
                if (!(outc(closure, ' ') &&
                      outname(closure, p->name) &&
                      outs(closure, "=\"", 2) &&
                      escape(closure, p->value,
                             attribute_entities, lengthof(attribute_entities)) &&
                      outc(closure, '"')))
                        abort();
        }
        // TODO Handle datatypeLibrary.
        if (element->children.first == NULL && !outc(closure, '/'))
                abort();
        if (!outc(closure, '>'))
                abort();
        if (is_indent(element)) {
                closure->indent++;
                indent(closure, closure->indent);
        }
        return true;
}

static bool
xml_enter_text(struct text *text, struct xml_closure *closure)
{
        if (!escape(closure, text->string, text_entities,
                    lengthof(text_entities)))
                abort();
        return true;
}

static bool
xml_enter(struct child *child, void *closure)
{
        switch (child->type) {
        case CHILD_TYPE_ELEMENT:
                return xml_enter_element((struct element *)child,
                                         (struct xml_closure *)closure);
                break;
        case CHILD_TYPE_TEXT:
                return xml_enter_text((struct text *)child,
                                      (struct xml_closure *)closure);
                break;
        default:
                abort();
        }
}

static bool
xml_leave_element(struct element *element, struct xml_closure *closure)
{
        if (is_indent(element)) {
                closure->indent--;
                indent(closure, closure->indent);
        }
        if (element->children.first != NULL &&
            !(outs(closure, "</", 2) &&
              outname(closure, element->name) &&
              outc(closure, '>')))
                abort();
        return true;
}

static bool
xml_leave(struct child *child, void *closure)
{
        switch (child->type) {
        case CHILD_TYPE_ELEMENT:
                return xml_leave_element((struct element *)child,
                                         (struct xml_closure *)closure);
                break;
        case CHILD_TYPE_TEXT:
                return true;
        default:
                abort();
        }
}

static bool
output_xml(struct parser *parser)
{
        struct xml_closure closure = { &parser->environment, 0 };
        static char xml_header[] = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
        return outs(&closure, xml_header, sizeof(xml_header) - 1) &&
                child_traverse(&parser->top_level->self, xml_enter, xml_leave,
                               &closure) &&
                outc(&closure, '\n');
}

int main(void)
{
        char buf[5000];
        buf[fread(buf, sizeof(char), sizeof(buf) - 1, stdin)] = '\0';
        struct parser parser = {
                .p = buf,
                .location = { 1, 1, 1, 1 },
                .environment = { NULL, NULL, inherit },
                .top_level = NULL,
                .errors = { NULL, NULL }
        };
        if (bind_prefix(&parser.environment, prefix_xml, uri_xml) == NULL ||
            bind_datatype_prefix(&parser.environment, prefix_xsd,
                                 uri_xsd) == NULL)
                parser_oom(&parser);
        else if (yyparse(&parser) == 0)
                output_xml(&parser);
        return EXIT_SUCCESS;
}
