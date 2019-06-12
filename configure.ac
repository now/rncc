AC_PREREQ([2.69])
AC_INIT([rncc], m4_esyscmd([build/git-version]), [now@disu.se])
PACKAGE_VERSION_MM=m4_bpatsubst(AC_PACKAGE_VERSION, [^\([0-9][0-9]*\.[0-9][0-9]*\).*$], [\1])
AC_SUBST([PACKAGE_VERSION_MM])
AC_CONFIG_AUX_DIR([build])
AC_CONFIG_MACRO_DIR([build/m4])
AC_CONFIG_SRCDIR([src/rncc.c])
AC_CONFIG_TESTDIR([tests], [tests])
AM_INIT_AUTOMAKE([1.15 foreign silent-rules subdir-objects -Wall -Werror])
AM_MISSING_PROG([AUTOM4TE], [autom4te])
AM_PROG_AR
AC_PROG_AWK
AC_PROG_CC_C99
AM_PROG_CC_C_O
AC_PROG_CPP_WERROR
AC_PROG_RANLIB
AC_PROG_YACC

AC_ARG_ENABLE([gcc-warnings],
[  --enable-gcc-warnings   turn on lots of GCC warnings],
[case "${enableval}" in
    yes|no) ;;
    *)      AC_MSG_ERROR([bad value ${enableval} for gcc-warnings option]) ;;
 esac],
 [enableval=no])
if test "${enableval}" = yes; then
  gl_WARN_ADD([-pedantic])
  gl_WARN_ADD([-Werror], [WERROR_CFLAGS])
  gl_WARN_ADD([-Wall])
  gl_WARN_ADD([-Wassign-enum])
  gl_WARN_ADD([-Wcast-align])
  gl_WARN_ADD([-Wcast-qual])
  gl_WARN_ADD([-Wconversion], [WCONVERSION_CFLAGS])
  gl_WARN_ADD([-Wextra])
  gl_WARN_ADD([-Wfor-loop-analysis])
  gl_WARN_ADD([-Wformat-pedantic])
  gl_WARN_ADD([-Wformat=2])
  gl_WARN_ADD([-Wimplicitly-unsigned-literal])
  gl_WARN_ADD([-Winit-self])
  gl_WARN_ADD([-Winline])
  gl_WARN_ADD([-Wmissing-braces], [WMISSINGBRACES_CFLAGS])
  gl_WARN_ADD([-Wmissing-declarations])
  gl_WARN_ADD([-Wmissing-format-attribute])
  gl_WARN_ADD([-Wmissing-include-dirs])
  gl_WARN_ADD([-Wmissing-noreturn])
  gl_WARN_ADD([-Wmissing-prototypes])
  gl_WARN_ADD([-Wmissing-variable-declarations])
  gl_WARN_ADD([-Wnested-externs])
  gl_WARN_ADD([-Wold-style-definition])
  gl_WARN_ADD([-D_FORTIFY_SOURCE=2])
  gl_WARN_ADD([-Wpacked])
  gl_WARN_ADD([-Wpointer-arith])
  gl_WARN_ADD([-Wshadow])
  gl_WARN_ADD([-Wshift-sign-overflow])
  gl_WARN_ADD([-Wsign-compare])
  gl_WARN_ADD([-Wstrict-aliasing=2])
  gl_WARN_ADD([-Wsuggest-attribute=const])
  gl_WARN_ADD([-Wsuggest-attribute=format])
  gl_WARN_ADD([-Wsuggest-attribute=noreturn])
  gl_WARN_ADD([-Wsuggest-attribute=pure], [WSUGGESTATTRIBUTEPURE_CFLAGS])
  gl_WARN_ADD([-Wundef])
  gl_WARN_ADD([-Wuninitialized])
  gl_WARN_ADD([-Wwrite-strings])
  if test -n "$WCONVERSION_CFLAGS"; then
    AC_DEFINE([HAVE_WCONVERSION], [1],
              [Define to 1 if compiler supports -Wconversion.])
  fi
  if test -n "$WMISSINGBRACES_CFLAGS"; then
    AC_DEFINE([HAVE_WMISSINGBRACES], [1],
              [Define to 1 if compiler supports -Wmissing-braces.])
  fi
  if test -n "$WSUGGESTATTRIBUTEPURE_CFLAGS"; then
    AC_DEFINE([HAVE_WSUGGESTATTRIBUTE_PURE], [1],
              [Define to 1 if compiler supports -Wsuggestattribute=pure.])
  fi
fi

AC_CONFIG_HEADERS([config.h])
AC_CONFIG_FILES([
  Makefile
  tests/atlocal
])
AC_OUTPUT
