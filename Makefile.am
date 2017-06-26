BUILT_SOURCES = $(top_srcdir)/.version
$(top_srcdir)/.version: configure
	$(AM_V_GEN)echo $(VERSION) > $@.tmp
	$(AM_V_at)mv $@.tmp $@
dist-hook:
	$(AM_V_GEN)echo $(VERSION) > $(distdir)/.tarball-version

AM_CFLAGS = $(WARN_CFLAGS) $(WERROR_CFLAGS)

AM_YFLAGS = --warnings=all,error --report=all

.PHONY: gtags
gtags: $(srcdir)/GRTAGS

$(srcdir)/GRTAGS: $(srcdir)/gtags.files
	$(AM_V_GEN)$(am__cd) $(srcdir) && gtags -i

$(srcdir)/gtags.files: $(am__tagged_files)
	$(AM_V_GEN)rm -f $@
	$(AM_V_at)$(am__cd) $(srcdir) && \
	  sdir=`pwd`; \
	  bdir=`awk -v b="$(abs_builddir)" -v s="$$sdir" \
	    'BEGIN { print substr(b, length(s) + 2) }'`; \
	  for file in $(am__tagged_files); do \
	    list="$$list `test -f $$file || echo $$bdir/`$$file"; \
	  done; \
	  printf "%s\n" $$list | LC_ALL=C sort -u > gtags.files

.PHONY: clean-gtags
clean-gtags:
	-rm -f $(srcdir)/GPATH $(srcdir)/GRTAGS $(srcdir)/GTAGS \
	  $(srcdir)/gtags.files

distclean-local: clean-gtags

bin_PROGRAMS = src/rncc

src_rncc_SOURCES = \
	src/rncc.y

check_SCRIPTS = tests/rncc

tests/rncc: tests/rncc.in
	$(AM_V_GEN)sed \
	  -e 's|@SHELL[@]|$(SHELL)|g' \
	  -e 's|@abs_top_builddir[@]|$(abs_top_builddir)|g' \
	  -e 's|@abs_top_srcdir[@]|$(abs_top_srcdir)|g' $< > $@.tmp
	$(AM_V_at)chmod a+x $@.tmp
	$(AM_V_at)mv $@.tmp $@

TESTSUITE_AT = \
	tests/decl.at \
	tests/local.at

TESTSUITE = tests/testsuite

EXTRA_DIST = \
	     tests/atlocal.in \
	     tests/package.m4 \
	     tests/testsuite.at \
	     $(TESTSUITE_AT) \
	     $(TESTSUITE)

RUN_TESTSUITE = $(SHELL) $(TESTSUITE) -C tests $(TESTSUITEFLAGS)

AUTOTEST = $(AUTOM4TE) --language=autotest
AUTOTESTFLAGS = -I $(srcdir)/tests

$(srcdir)/tests/package.m4: $(srcdir)/configure.ac
	$(AM_V_GEN)rm -f $@ $@.tmp
	$(AM_V_at){ \
	  echo 'm4_define([AT_PACKAGE_NAME], [$(PACKAGE_NAME)])' && \
	  echo 'm4_define([AT_PACKAGE_TARNAME], [$(PACKAGE_TARNAME)])' && \
	  echo 'm4_define([AT_PACKAGE_VERSION], [$(PACKAGE_VERSION)])' && \
	  echo 'm4_define([AT_PACKAGE_STRING], [$(PACKAGE_STRING)])' && \
	  echo 'm4_define([AT_PACKAGE_BUGREPORT], [$(PACKAGE_BUGREPORT)])' && \
	  echo 'm4_define([AT_PACKAGE_URL], [$(PACKAGE_URL)])'; \
	} > $@.tmp
	$(AM_V_at)mv $@.tmp $@

$(TESTSUITE): tests/testsuite.at tests/package.m4 $(TESTSUITE_AT)
	$(AM_V_GEN)$(AUTOTEST) $(AUTOTESTFLAGS) -o $@.tmp $<
	$(AM_V_at)mv $@.tmp $@

check-local: tests/atconfig tests/atlocal $(TESTSUITE)
	@echo '$(TESTSUITE): Entering directory `tests'\'
	$(RUN_TESTSUITE)
	@echo '$(TESTSUITE): Leaving directory `tests'\'

installcheck-local: tests/atconfig tests/atlocal $(TESTSUITE)
	@echo '$(TESTSUITE): Entering directory `tests'\'
	$(RUN_TESTSUITE) AUTOTEST_PATH='$(bindir)'
	@echo '$(TESTSUITE): Leaving directory `tests'\'

clean-local:
	if test -f '$(TESTSUITE)'; then \
	  echo '$(TESTSUITE): Entering directory `tests'\'; \
	  $(SHELL) $(TESTSUITE) -C tests --clean; \
	  echo '$(TESTSUITE): Leaving directory `tests'\'; \
	fi