EMACS ?= emacs
export DJOT_GRAMMAR_DIR

.PHONY: check test compile checkdoc benchmark clean
check: compile checkdoc test

compile:
	$(EMACS) -Q --batch -L . --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile djot-modern.el

checkdoc:
	$(EMACS) -Q --batch -l test/checkdoc.el

test:
	$(EMACS) -Q --batch -L . -l test/setup.el -l test/djot-modern-test.el -f ert-run-tests-batch-and-exit

benchmark:
	$(EMACS) -Q --batch -L . -l test/setup.el -l test/benchmark.el

clean:
	rm -f djot-modern.elc
