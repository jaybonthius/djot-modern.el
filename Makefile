EMACS ?= emacs
DJOT_MODE_DIR ?= ../emacs-djot-mode
GRAMMAR_DIR ?=
BATCH = $(EMACS) -Q --batch -L . -L $(DJOT_MODE_DIR) -l test/setup.el
export GRAMMAR_DIR

.PHONY: check test integration compile checkdoc benchmark clean
check: compile checkdoc test
compile:
	$(BATCH) --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile djot-modern.el
checkdoc:
	$(BATCH) -l test/checkdoc.el
test:
	$(BATCH) -l test/djot-modern-test.el -l test/table-integration-test.el -f ert-run-tests-batch-and-exit
integration: test
benchmark:
	$(BATCH) -l test/benchmark.el
clean:
	rm -f djot-modern.elc
