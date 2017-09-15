#include <errno.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <def.h>
#include <io-in.h>
#include <io-out.h>
#include <io-std.h>
#include <io-static-out.h>
#include <io-stynamic-out.h>
#include <location.h>
#include <error.h>
#include <rncc.h>
#include <tests/tap.h>

static struct test {
        const char *description;
        struct string in;
        struct string expected;
        struct string error;
} tests[] = {
#define STRING(s) { s, sizeof(s) - 1 }
#define E(d, in, error) { d, STRING(in), STRING(""), STRING(error) }
#define X(d, in, expected) { \
        d, \
        STRING(in), \
        STRING("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" expected "\n"), \
        { NULL, 0 } \
}
#define G(d, in, expected) \
        X(d, in, \
          "<grammar xmlns=\"http://relaxng.org/ns/structure/1.0\">\n" \
          expected \
          "</grammar>")
#define L(d, in, expected) \
        X(d, in, \
          "<value xmlns=\"http://relaxng.org/ns/structure/1.0\">" \
          expected \
          "</value>")
#define N(d, in, expected) \
        X(d, in, \
          "<element xmlns=\"http://relaxng.org/ns/structure/1.0\">\n" \
          expected "\n" \
          "</element>")
#define A(d, in, expected) \
        X(d, in, \
          "<attribute xmlns=\"http://relaxng.org/ns/structure/1.0\">\n" \
          expected "\n" \
          "</attribute>")
        // Escape sequence
        E("Incomplete escape sequence", "\\x{fffd",
          "1.1-7: error: incomplete escape sequence; skipping"),
        E("Replacement character", u8"�",
          u8"1:1: error: character ‘�’ (U+FFFD) isn’t allowed; skipping"),
        E("Escaped replacement character", "\\x{fffd}",
          u8"1.1-8: error: character ‘�’ (U+FFFD) isn’t allowed; skipping"),
        E("Escaped replacement character", "\xff",
          "1:1: error: illegal UTF-8 byte sequence; skipping"),
        L("Escape sequence", "'\\x{61}'", "a"),
        L("Escape sequence with multiple xes", "'\\xxx{61}'", "a"),
        // Comments
        X("Comment (1)", "# This is a comment",
          "<grammar xmlns=\"http://relaxng.org/ns/structure/1.0\"/>"),
        // Comments
        L("Comment (2)",
          "# This is a comment\n"
          "''", ""),
        // Literals
        L("Empty literal", "''", ""),
        L("Empty literal using escaped quotes", "\\x{27}\\x{27}", ""),
        L("Simple single-quoted literal", "'a'", "a"),
        L("Simple double-quoted literal", "\"a\"", "a"),
        L("Empty triple-single-quoted literal", "''''''", ""),
        L("Empty triple-double-quoted literal", "\"\"\"\"\"\"", ""),
        L("Triple-single-quoted literal", "'''a'''", "a"),
        L("Triple-double-quoted literal", "\"\"\"a\"\"\"", "a"),
        L("Complex triple-quoted literal", "'''a''a'''", "a''a"),
        L("Complex triple-quoted literal w/escape", "'''a\\x{27}'a'''", "a''a"),
        L("Concatenated empty literal", "''~''", ""),
        L("Concatenated literal", "'a'~'b'", "ab"),
        L("Concatenated literal with escape (1)", "'\\x{61}'~'b'", "ab"),
        L("Concatenated literal with escape (2)", "'a'~'\\x{62}'", "ab"),
        E("Incomplete literal at EOF", "'",
          "1:1: error: expected ‘'’ after literal content"),
        E("Incomplete literal at EOL (1)", "'\n",
          "1:1: error: expected ‘'’ after literal content"),
        E("Incomplete literal at EOL (2)", "'a\n",
          "1.1-2: error: expected ‘'’ after literal content"),
        E("Incomplete triple-quoted literal at EOF (1)", "'''",
          "1.1-3: error: expected “'''” after literal content"),
        E("Incomplete triple-quoted literal at EOF (2)", "''''",
          "1.1-4: error: expected “'''” after literal content"),
        E("Incomplete triple-quoted literal at EOF (3)", "'''''",
          "1.1-5: error: expected “'''” after literal content"),
        E("Incomplete triple-quoted literal at EOF (4)", "'''\n",
          "1.1-3: error: expected “'''” after literal content"),
        E("Incomplete triple-quoted literal at EOF (5)", "''''\n",
          "1.1-4: error: expected “'''” after literal content"),
        E("Incomplete triple-quoted literal at EOF (6)", "'''''\n",
          "1.1-5: error: expected “'''” after literal content"),
        // Identifiers
        E("Backslash at end of file", "\\",
          "1:1: error: unexpected ‘\\’ (U+005C) at end of input"),
        E("Illegal identifier", "0",
          "1:1: error: unexpected ‘0’ (U+0030) in input; skipping"),
        // TODO What about this?  Range is a bit weird.
        E("Escaped illegal identifier", "\\0",
          "1.1-2: error: unexpected ‘0’ (U+0030) in input; skipping"),
        // Declarations
        E("Incomplete element definition",
          "namespace a = 'n' start = element a:*",
          "1:38: error: syntax error, unexpected end of file, expecting '{'"),
        E("Incomplete namespaced identifier at EOF",
          "namespace a = 'n' start = element a:",
          "1.35-36: error: incomplete CName; treating it as *\n"
          "1:37: error: syntax error, unexpected end of file, expecting '{'"),
        E("Incomplete namespaced identifier at EOL",
          "namespace a = 'n' start = element a:\n",
          "1.35-36: error: incomplete CName; treating it as *\n"
          "2:1: error: syntax error, unexpected end of file, expecting '{'"),
        N("Complete namespaced identifier",
          "namespace a = 'n' element a:b { empty }",
          "  <name ns=\"n\">b</name>\n"
          "  <empty/>"),
        E("Xml prefix bound to incorrect URI", "namespace xml = 'n'",
          "1.17-19: error: prefix “xml” can only be bound to namespace URI "
          "“http://www.w3.org/XML/1998/namespace”"),
        E("Incorrect prefix bound to XML namespace URI",
          "namespace x = 'http://www.w3.org/XML/1998/namespace'",
          "1:11: error: only prefix “xml” can be bound to namespace URI "
          "“http://www.w3.org/XML/1998/namespace”"),
        // This one is a bit weird, but if you follow the constraints
        // to the letter, declaring the xml prefix should actually
        // result in this error being reported.
        E("Xml prefix namespace declaration",
          "namespace xml = 'http://www.w3.org/XML/1998/namespace'",
          "1.1-54: error: prefix “xml” has already been bound to "
          "“http://www.w3.org/XML/1998/namespace” in the initial environment"),
        X("Namespace declaration", "namespace a = 'n'",
          "<grammar xmlns=\"http://relaxng.org/ns/structure/1.0\"/>"),
        E("Duplicate namespace declaration",
          "namespace a = 'n' namespace a = 'n'",
          "1.19-35: error: prefix “a” has already been bound to “n”\n"
          "1.1-17: note: previous binding of “a” was made here"),
        E("Default namespace set to XML namespace URI",
          "default namespace = 'http://www.w3.org/XML/1998/namespace'",
          "1.21-58: error: default namespace can’t be set to "
          "“http://www.w3.org/XML/1998/namespace”"),
        N("Default namespace", "default namespace = 'n' element b { empty }",
          "  <name ns=\"n\">b</name>\n"
          "  <empty/>"),
        E("Duplicate default namespace with same URI",
          "default namespace = 'a' default namespace = 'a'",
          "1.25-47: error: default namespace has already been set to “a”\n"
          "1.1-23: note: it was set here"),
        E("Duplicate default namespace with different URI",
          "default namespace = 'a' default namespace = 'b'",
          "1.25-47: error: default namespace has already been set to “a”\n"
          "1.1-23: note: it was set here"),
        E("Default ns w/xml prefix bound to incorrect URI",
          "default namespace xml = 'n'",
          "1.25-27: error: prefix “xml” can only be bound to namespace URI "
          "“http://www.w3.org/XML/1998/namespace”"),
        E("Default ns w/incorrect prefix b to XML ns URI",
          "default namespace x = 'http://www.w3.org/XML/1998/namespace'",
          "1:19: error: only prefix “xml” can be bound to namespace URI "
          "“http://www.w3.org/XML/1998/namespace”\n"
          "1.23-60: error: default namespace can’t be set to "
          "“http://www.w3.org/XML/1998/namespace”"),
        // This one is a bit weird, but if you follow the constraints
        // to the letter, declaring the xml prefix should actually
        // result in this error being reported.
        E("Default ns with xml prefix declaration",
          "default namespace xml = 'http://www.w3.org/XML/1998/namespace'",
          "1.1-62: error: prefix “xml” has already been bound to "
          "“http://www.w3.org/XML/1998/namespace” in the initial environment\n"
          "1.25-62: error: default namespace can’t be set to "
          "“http://www.w3.org/XML/1998/namespace”"),
        N("Default namespace with prefix",
          "default namespace a = 'n' element a:b { element c { empty } }",
          "  <name ns=\"n\">b</name>\n"
          "  <element>\n"
          "    <name ns=\"n\">c</name>\n"
          "    <empty/>\n"
          "  </element>"),
        E("Duplicate default ns declaration w/prefix (1)",
          "default namespace a = 'n' namespace a = 'n'",
          "1.27-43: error: prefix “a” has already been bound to “n”\n"
          "1.1-25: note: previous binding of “a” was made here"),
        E("Duplicate default ns declaration w/prefix (2)",
          "namespace a = 'n' default namespace a = 'n'",
          "1.19-43: error: prefix “a” has already been bound to “n”\n"
          "1.1-17: note: previous binding of “a” was made here"),
        N("Empty and non-empty namespace",
          "default namespace a='n'namespace l=''element a:b{element l:c{empty}}",
          "  <name ns=\"n\">b</name>\n"
          "  <element>\n"
          "    <name ns=\"\">c</name>\n"
          "    <empty/>\n"
          "  </element>"),
        E("Broken datatypes URI", "datatypes a = 'b:c d'",
          "1:19: error: invalid URI content starting here"),
        E("Broken datatypes URI over multiple lines",
          "datatypes a = 'b:c'~\n"
          "  ''' d'''",
          "2:6: error: invalid URI content starting here"),
        E("Xsd prefix bound to incorrect URI", "datatypes xsd = 'n'",
          "1.17-19: error: prefix “xsd” can only be bound to namespace URI "
          "“http://www.w3.org/2001/XMLSchema-datatypes”"),
        // This one is a bit weird, but if you follow the constraints
        // to the letter, declaring the xml prefix should actually
        // result in this error being reported.
        E("Xsd prefix namespace declaration",
          "datatypes xsd = 'http://www.w3.org/2001/XMLSchema-datatypes'",
          "1.1-60: error: prefix “xsd” has already been bound to "
          "“http://www.w3.org/2001/XMLSchema-datatypes” in the initial "
          "environment"),
        E("Datatypes with relative URI",
          "datatypes a = 'n'",
          "1.15-17: error: datatypes URI mustn’t be relative"),
        E("Datatypes with URI with fragment identifier",
          "datatypes a = 'n:m#o'",
          "1.19-20: error: datatypes URI mustn’t include a fragment identifier"),
        E("Datatypes with URI with fragment identifier over multiple literals",
          "datatypes a = 'b:c#'~\n"
          "  '''d'''",
          "1.19-2.6: error: datatypes URI mustn’t include a fragment "
          "identifier"),
        N("Datatypes declaration", "datatypes a = 'n:' element b { a:c }",
          "  <name>b</name>\n"
          "  <data datatypeLibrary=\"n:\" type=\"c\"/>"),
        // Namespace prefix
        E("Illegal namespace prefix", "namespace xmlns = 'n'",
          "1.11-15: error: namespace prefix must not be “xmlns”"),
        // Namespace URI literal
        X("Namespace inherit", "namespace a = inherit",
          "<grammar xmlns=\"http://relaxng.org/ns/structure/1.0\"/>"),
        // Grammar
        G("Two defines", "a = element b { empty } c = element d { empty }",
          "  <define name=\"a\">\n"
          "    <element>\n"
          "      <name>b</name>\n"
          "      <empty/>\n"
          "    </element>\n"
          "  </define>\n"
          "  <define name=\"c\">\n"
          "    <element>\n"
          "      <name>d</name>\n"
          "      <empty/>\n"
          "    </element>\n"
          "  </define>\n"),
        // Annotated component
        E("Duplicate annotation attribute",
          "namespace a = 'n' start = [a:b='1' a:b='2'] empty",
          "1.36-42: error: attribute with namespace URI “n” and local name “b” "
          "has already been set\n"
          "1.28-34: note: it was previously set here"),
        E("Foreign attribute name using xmlns URI",
          "namespace a = 'http://www.w3.org/2000/xmlns' [a:b='1'] empty",
          "1.47-49: error: annotation attribute can’t have namespace URI "
          "“http://www.w3.org/2000/xmlns”"),
        E("Foreign attribute with unqualified name",
          "namespace a = '' [a:b='1'] empty",
          "1.19-21: error: annotation attribute must have a namespace URI"),
        E("Foreign attribute name using Relax NG namespace",
          "namespace a = 'http://relaxng.org/ns/structure/1.0' [a:b='1'] empty",
          "1.54-56: error: annotation attribute can’t have namespace URI "
          "“http://relaxng.org/ns/structure/1.0”"),
        E("Nested foreign attribute name using Relax NG namespace",
          "namespace a = 'http://www.w3.org/2000/xmlns'\n"
          "namespace b = 'n'\n"
          "[b:c[a:d='1']] empty",
          "3.6-8: error: annotation attribute can’t have namespace URI "
          "“http://www.w3.org/2000/xmlns”"),
        E("Foreign element name using Relax NG namespace",
          "namespace a = 'http://relaxng.org/ns/structure/1.0' [a:b['1']] empty",
          "1.54-56: error: annotation element can’t have namespace URI "
          "“http://relaxng.org/ns/structure/1.0”"),
        X("Annotated component", "namespace a='n' [a:b='' c[]]element d {empty}",
          "<element xmlns=\"http://relaxng.org/ns/structure/1.0\" "
          "xmlns:a=\"n\" a:b=\"\">\n"
          "  <c/>\n"
          "  <name>d</name>\n"
          "  <empty/>\n"
          "</element>"),
        // Start
        G("Start", "start = empty",
          "  <start>\n"
          "    <empty/>\n"
          "  </start>\n"),
        // Define
        G("Define", "a = empty",
          "  <define name=\"a\">\n"
          "    <empty/>\n"
          "  </define>\n"),
        // Assign op
        G("Define", "a |= empty",
          "  <define name=\"a\" combine=\"choice\">\n"
          "    <empty/>\n"
          "  </define>\n"),
        G("Define", "a &= empty",
          "  <define name=\"a\" combine=\"interleave\">\n"
          "    <empty/>\n"
          "  </define>\n"),
        // Include
        E("Broken include URI", "include 'a b'",
          "1:11: error: invalid URI content starting here"),
        E("Broken include URI over multiple literals", "include 'a'~' b'",
          "1:14: error: invalid URI content starting here"),
        G("Include without inherit and body", "include 'a'",
          "  <include href=\"a\"/>\n"),
        G("Include without inherit and body with default ns",
          "default namespace = 'n' include 'a'",
          "  <include href=\"a\" ns=\"n\"/>\n"),
        G("Include with empty inherit without body",
          "namespace a = '' include 'b' inherit = a",
          "  <include href=\"b\" ns=\"\"/>\n"),
        G("Include with non-empty inherit without body",
          "namespace a = 'n' include 'b' inherit = a",
          "  <include href=\"b\" ns=\"n\"/>\n"),
        G("Include without inherit with body",
          "include 'b' { a = empty }",
          "  <include href=\"b\">\n"
          "    <define name=\"a\">\n"
          "      <empty/>\n"
          "    </define>\n"
          "  </include>\n"),
        G("Include with inherit with body",
          "namespace a = 'n' include 'b' inherit = a { c = empty }",
          "  <include href=\"b\" ns=\"n\">\n"
          "    <define name=\"c\">\n"
          "      <empty/>\n"
          "    </define>\n"
          "  </include>\n"),
        // TODO Improve this error message, should be “include not
        // allowed inside include”.  We should use something like what
        // Russ Cox used in
        // https://github.com/tardisgo/tardisgo/blob/master/goroot/haxe/go1.4/src/cmd/gc/bisonerrors
        // https://github.com/tardisgo/tardisgo/blob/3c511706e5d7af9a5eee5ba572201967ab3e1cfc/goroot/haxe/go1.4/src/cmd/gc/subr.c
        // https://github.com/tardisgo/tardisgo/blob/master/goroot/haxe/go1.4/src/cmd/gc/go.errors
        E("Include within include", "include 'a' { include 'b' }\n",
          "1.15-21: error: syntax error, unexpected include, expecting div or "
          "start or CName or identifier"),
        // Div
        G("Empty div element", "div { }",
          "  <div/>\n"),
        G("Div element", "div { start = empty }",
          "  <div>\n"
          "    <start>\n"
          "      <empty/>\n"
          "    </start>\n"
          "  </div>\n"),
        // Pattern
        X("Choice", "'a' | 'b'",
          "<choice xmlns=\"http://relaxng.org/ns/structure/1.0\">\n"
          "  <value>a</value>\n"
          "  <value>b</value>\n"
          "</choice>"),
        X("Tripple choice", "'a' | 'b' | 'c'",
          "<choice xmlns=\"http://relaxng.org/ns/structure/1.0\">\n"
          "  <value>a</value>\n"
          "  <value>b</value>\n"
          "  <value>c</value>\n"
          "</choice>"),
        X("Group", "'a', 'b'",
          "<group xmlns=\"http://relaxng.org/ns/structure/1.0\">\n"
          "  <value>a</value>\n"
          "  <value>b</value>\n"
          "</group>"),
        X("Tripple group", "'a', 'b', 'c'",
          "<group xmlns=\"http://relaxng.org/ns/structure/1.0\">\n"
          "  <value>a</value>\n"
          "  <value>b</value>\n"
          "  <value>c</value>\n"
          "</group>"),
        X("Interleave", "'a' & 'b'",
          "<interleave xmlns=\"http://relaxng.org/ns/structure/1.0\">\n"
          "  <value>a</value>\n"
          "  <value>b</value>\n"
          "</interleave>"),
        X("Tripple interleave", "'a' & 'b' & 'c'",
          "<interleave xmlns=\"http://relaxng.org/ns/structure/1.0\">\n"
          "  <value>a</value>\n"
          "  <value>b</value>\n"
          "  <value>c</value>\n"
          "</interleave>"),
        // Inner particle
        X("Inner particle", "namespace a='n' start=empty* >> a:c []",
          "<grammar xmlns=\"http://relaxng.org/ns/structure/1.0\" "
          "xmlns:a=\"n\">\n"
          "  <start>\n"
          "    <zeroOrMore>\n"
          "      <empty/>\n"
          "    </zeroOrMore>\n"
          "    <a:c/>\n"
          "  </start>\n"
          "</grammar>"),
        // Repeated primary
        X("Repeated primary zeroOrMore", "empty*",
          "<zeroOrMore xmlns=\"http://relaxng.org/ns/structure/1.0\">\n"
          "  <empty/>\n"
          "</zeroOrMore>"),
        X("Repeated primary oneOrMore", "empty+",
          "<oneOrMore xmlns=\"http://relaxng.org/ns/structure/1.0\">\n"
          "  <empty/>\n"
          "</oneOrMore>"),
        X("Repeated primary optional", "empty?",
          "<optional xmlns=\"http://relaxng.org/ns/structure/1.0\">\n"
          "  <empty/>\n"
          "</optional>"),
        // Primary
        N("Element", "element a { empty }",
          "  <name>a</name>\n"
          "  <empty/>"),
        N("Element with default namespace name",
          "default namespace = 'n' element a { empty }",
          "  <name ns=\"n\">a</name>\n"
          "  <empty/>"),
        A("Attribute", "attribute a { empty }",
          "  <name ns=\"\">a</name>\n"
          "  <empty/>"),
        A("Attribute without default namespace name",
          "default namespace = 'n' attribute a { empty }",
          "  <name ns=\"\">a</name>\n"
          "  <empty/>"),
        X("Mixed", "mixed { empty }",
          "<mixed xmlns=\"http://relaxng.org/ns/structure/1.0\">\n"
          "  <empty/>\n"
          "</mixed>"),
        X("List", "list { empty }",
          "<list xmlns=\"http://relaxng.org/ns/structure/1.0\">\n"
          "  <empty/>\n"
          "</list>"),
        X("String data", "string",
          "<data xmlns=\"http://relaxng.org/ns/structure/1.0\" "
          "datatypeLibrary=\"\" type=\"string\"/>"),
        X("Token data", "token",
          "<data xmlns=\"http://relaxng.org/ns/structure/1.0\" "
          "datatypeLibrary=\"\" type=\"token\"/>"),
        X("String data with params", "xsd:string { maxLength='1' }",
          "<data xmlns=\"http://relaxng.org/ns/structure/1.0\" "
          "datatypeLibrary=\"http://www.w3.org/2001/XMLSchema-datatypes\" "
          "type=\"string\">\n"
          "  <param name=\"maxLength\">1</param>\n"
          "</data>"),
        X("Value with type", "string '1'",
          "<value xmlns=\"http://relaxng.org/ns/structure/1.0\" "
          "datatypeLibrary=\"\" type=\"string\">1</value>"),
        L("Value", "'1'", "1"),
        X("Empty", "empty",
          "<empty xmlns=\"http://relaxng.org/ns/structure/1.0\"/>"),
        X("NotAllowed", "notAllowed",
          "<notAllowed xmlns=\"http://relaxng.org/ns/structure/1.0\"/>"),
        X("Text", "text",
          "<text xmlns=\"http://relaxng.org/ns/structure/1.0\"/>"),
        X("Ref", "a",
          "<ref xmlns=\"http://relaxng.org/ns/structure/1.0\" name=\"a\"/>"),
        X("ParentRef", "parent a",
          "<parentRef xmlns=\"http://relaxng.org/ns/structure/1.0\" "
          "name=\"a\"/>"),
        G("Grammar", "grammar{start=grammar{start=grammar{start=empty}}}",
          "  <start>\n"
          "    <grammar>\n"
          "      <start>\n"
          "        <grammar>\n"
          "          <start>\n"
          "            <empty/>\n"
          "          </start>\n"
          "        </grammar>\n"
          "      </start>\n"
          "    </grammar>\n"
          "  </start>\n"),
        // External
        E("Broken external URI", "external 'a b'",
          "1:12: error: invalid URI content starting here"),
        X("External without inherit", "external 'a'",
          "<externalRef xmlns=\"http://relaxng.org/ns/structure/1.0\" "
          "href=\"a\"/>"),
        X("External without inherit with default ns",
          "default namespace = 'n' external 'a'",
          "<externalRef xmlns=\"http://relaxng.org/ns/structure/1.0\" "
          "href=\"a\" ns=\"n\"/>"),
        X("External with empty inherit",
          "namespace a = '' external 'b' inherit = a",
          "<externalRef xmlns=\"http://relaxng.org/ns/structure/1.0\" "
          "href=\"b\" ns=\"\"/>"),
        X("External with non-empty inherit",
          "namespace a = 'n' external 'b' inherit = a",
          "<externalRef xmlns=\"http://relaxng.org/ns/structure/1.0\" "
          "href=\"b\" ns=\"n\"/>"),
        // Data except
        X("Data except", "string - ('a', 'b')",
          "<data xmlns=\"http://relaxng.org/ns/structure/1.0\" "
          "datatypeLibrary=\"\" type=\"string\">\n"
          "  <except>\n"
          "    <group>\n"
          "      <value>a</value>\n"
          "      <value>b</value>\n"
          "    </group>\n"
          "  </except>\n"
          "</data>"),
        // Datatype name
        E("Undefined datatype prefix", "a:b",
          "1:1: error: undeclared prefix “a”"),
        // Element name class
        N("Element name class", "element a|b { empty }",
          "  <choice>\n"
          "    <name>a</name>\n"
          "    <name>b</name>\n"
          "  </choice>\n"
          "  <empty/>"),
        // Attribute name class
        A("Attribute name class", "attribute a|b { empty }",
          "  <choice>\n"
          "    <name ns=\"\">a</name>\n"
          "    <name ns=\"\">b</name>\n"
          "  </choice>\n"
          "  <empty/>"),
        // Annotated element names
        X("Annotated element name",
          "namespace a = 'n' element [a:b='1' a:c[]] d { empty }",
          "<element xmlns=\"http://relaxng.org/ns/structure/1.0\" "
          "xmlns:a=\"n\">\n"
          "  <name a:b=\"1\"><a:c/>d</name>\n"
          "  <empty/>\n"
          "</element>"),
        X("Annotated element name inside choice",
          "namespace a = 'n' element [a:b='1' a:c[]] (d) { empty }",
          "<element xmlns=\"http://relaxng.org/ns/structure/1.0\" "
          "xmlns:a=\"n\">\n"
          "  <choice a:b=\"1\">\n"
          "    <a:c/>\n"
          "    <name>d</name>\n"
          "  </choice>\n"
          "  <empty/>\n"
          "</element>"),
        X("Annotated element names",
          "namespace a = 'n' element [a:b='1' a:c[]] (d|e) { empty }",
          "<element xmlns=\"http://relaxng.org/ns/structure/1.0\" "
          "xmlns:a=\"n\">\n"
          "  <choice a:b=\"1\">\n"
          "    <a:c/>\n"
          "    <name>d</name>\n"
          "    <name>e</name>\n"
          "  </choice>\n"
          "  <empty/>\n"
          "</element>"),
        // Annotated attribute names
        X("Annotated attribute name",
          "namespace a = 'n' attribute [a:b='1' a:c[]] d { empty }",
          "<attribute xmlns=\"http://relaxng.org/ns/structure/1.0\" "
          "xmlns:a=\"n\">\n"
          "  <name ns=\"\" a:b=\"1\"><a:c/>d</name>\n"
          "  <empty/>\n"
          "</attribute>"),
        X("Annotated attribute name inside choice",
          "namespace a = 'n' attribute [a:b='1' a:c[]] (d) { empty }",
          "<attribute xmlns=\"http://relaxng.org/ns/structure/1.0\" "
          "xmlns:a=\"n\">\n"
          "  <choice a:b=\"1\">\n"
          "    <a:c/>\n"
          "    <name ns=\"\">d</name>\n"
          "  </choice>\n"
          "  <empty/>\n"
          "</attribute>"),
        X("Annotated element names",
          "namespace a = 'n' attribute [a:b='1' a:c[]] (d|e) { empty }",
          "<attribute xmlns=\"http://relaxng.org/ns/structure/1.0\" "
          "xmlns:a=\"n\">\n"
          "  <choice a:b=\"1\">\n"
          "    <a:c/>\n"
          "    <name ns=\"\">d</name>\n"
          "    <name ns=\"\">e</name>\n"
          "  </choice>\n"
          "  <empty/>\n"
          "</attribute>"),
        // Except name class
        N("Except ns-name class",
          "namespace a = 'n' element a:* - a:b { empty }",
          "  <nsName ns=\"n\">\n"
          "    <except>\n"
          "      <name ns=\"n\">b</name>\n"
          "    </except>\n"
          "  </nsName>\n"
          "  <empty/>"),
        N("Except any-name class",
          "element * - b { empty }",
          "  <anyName>\n"
          "    <except>\n"
          "      <name>b</name>\n"
          "    </except>\n"
          "  </anyName>\n"
          "  <empty/>"),
        // Simple element name class
        N("Simple element name class", "element element { empty }",
          "  <name>element</name>\n"
          "  <empty/>"),
        N("Simple element name class with default namespace",
          "default namespace = 'n' element element { empty }",
          "  <name ns=\"n\">element</name>\n"
          "  <empty/>"),
        // Simple attribute name class
        A("Simple attribute name class", "attribute attribute { empty }",
          "  <name ns=\"\">attribute</name>\n"
          "  <empty/>"),
        A("Simple attribute name class with default namespace",
          "default namespace = 'n' attribute attribute { empty }",
          "  <name ns=\"\">attribute</name>\n"
          "  <empty/>"),
        // Prefixed name
        E("Inherited annotation namespace",
          "namespace a = inherit [a:a='1'] element b { empty }",
          "1.24-26: error: namespace URI for annotation can’t be inherited"),
        // Follow annotations
        E("Stray > interpreted as >>", "namespace a='n' start=empty > a:b[]",
          "1:29: error: stray ‘>’ in input; interpreting it as “>>”"),
        X("Multiple follow annotations",
          "namespace a = 'n' start = empty >> a:b[c='1'] >> a:d['2']",
          "<grammar xmlns=\"http://relaxng.org/ns/structure/1.0\" "
          "xmlns:a=\"n\">\n"
          "  <start>\n"
          "    <empty/>\n"
          "    <a:b c=\"1\"/>\n"
          "    <a:d>2</a:d>\n"
          "  </start>\n"
          "</grammar>"),
        // UTF-16 input
        E("UTF-16LE input", "\xfe\xff",
          "1.1-2: error: UTF-16 input isn’t supported"),
        E("UTF-16BE input", "\xff\xfe",
          "1.1-2: error: UTF-16 input isn’t supported"),
        // Issues
        G("Don’t use “rng” prefix in output",
          "default namespace rng = 'http://relaxng.org/ns/structure/1.0'\n"
          "start = empty",
          "  <start>\n"
          "    <empty/>\n"
          "  </start>\n"),
        // This was caused by literals_to_string result being used in
        // namespace mapping and the result wasn’t marked as shared.
        G("Avoid double free when freeing attribute values",
          "a = attribute b { xsd:anyURI } c = attribute d { xsd:anyURI }",
          "  <define name=\"a\">\n"
          "    <attribute>\n"
          "      <name ns=\"\">b</name>\n"
          "      <data datatypeLibrary=\"http://www.w3.org/2001/XMLSchema-datatypes\" type=\"anyURI\"/>\n"
          "    </attribute>\n"
          "  </define>\n"
          "  <define name=\"c\">\n"
          "    <attribute>\n"
          "      <name ns=\"\">d</name>\n"
          "      <data datatypeLibrary=\"http://www.w3.org/2001/XMLSchema-datatypes\" type=\"anyURI\"/>\n"
          "    </attribute>\n"
          "  </define>\n"),
#undef STRING
#undef E
#undef X
#undef L
#undef N
};

static int
string_cmp(struct string *a, struct string *b)
{
        if (a->n == b->n)
                return memcmp(a->s, b->s, b->n);
        else {
                int c = memcmp(a->s, b->s, a->n < b->n ? a->n : b->n);
                return c != 0 ? c : a->n < b->n ? -1 : +1;
        }
}

int
main(UNUSED int argc, char **argv)
{
        int result = EXIT_SUCCESS, r;
        if ((r = plan(lengthof(tests))) < 0)
                goto error;
        struct io_stynamic_out o = IO_STYNAMIC_OUT_INIT(8192, realloc);
        struct errors errors = ERRORS_INIT(20, malloc);
        for (size_t i = 0; i < lengthof(tests); i++) {
                o.n = 0;
                errors.n = 0;
                int rs = rncc_parse(&o.self, &errors, tests[i].in.s,
                                    tests[i].in.n);
                struct string s = { o.s, o.n };
                bool same;
                if ((r = ok(tests[i].error.s == NULL ?
                            rs >= 0 && errors.n == 0 &&
                            (same = string_cmp(&s, &tests[i].expected) == 0) :
                            rs < 0 &&
                            (same = error_string_cmp(&errors,
                                                     &tests[i].error) == 0),
                            tests[i].description)) < 0)
                        goto error;
                else if (!r && tests[i].error.s == NULL) {
                        if ((r = io_print(io_stdout, "# expected     ")) < 0 ||
                            (r = print_string(&tests[i].in, 14)) < 0 ||
                            (r = io_print(io_stdout, "# to parse as  ")) < 0 ||
                            (r = print_string(&tests[i].expected, 14)) < 0 ||
                            (r = io_print(io_stdout, "# but got      ")) < 0 ||
                            (!same && (r = print_string(&s, 14)) < 0) ||
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
                            (s.n > 0 &&
                             ((r = io_print(io_stdout, "# %s parsed as ",
                                            !same ? "and" : "but")) < 0 ||
                              (r = print_string(&s, 15)) < 0)))
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
        if (io_stynamic_is_dynamic(&o))
                free(o.s);
        if (io_std_close(argv[0]) < 0)
                result = EXIT_FAILURE;
        return result;
}
