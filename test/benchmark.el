;;; benchmark.el --- Repeatable display measurements -*- lexical-binding: t; -*-

(require 'benchmark)
(require 'djot-modern)

(unless (treesit-ready-p 'djot t)
  (error "A ready Djot grammar is required; set DJOT_GRAMMAR_DIR if needed"))

(defconst djot-modern-benchmark--sample
  "# A heading\n\nA paragraph with *strong* and _emphasis_, [link](https://example.org).\n\n- item\n- [x] task\n\n```text\n# literal\n```\n\n| Key | Value |\n| --- | ----- |\n| a | b |\n\n")

(defun djot-modern-benchmark--time (function)
  "Time FUNCTION once, including garbage collection."
  (car (benchmark-call function 1)))

(defun djot-modern-benchmark--run (lines)
  "Measure initial rendering and three edit types over LINES of source."
  (with-temp-buffer
    (rename-buffer (generate-new-buffer-name "djot-modern-benchmark"))
    (text-mode)
    (dotimes (_ (/ lines 15)) (insert djot-modern-benchmark--sample))
    (dotimes (_ (% lines 15)) (insert "plain\n"))
    (let ((noninteractive nil) results)
      (push (djot-modern-benchmark--time
             (lambda () (djot-modern-mode 1) (font-lock-ensure))) results)
      ;; Drain any initial structural invalidation before timing local edits.
      (font-lock-ensure)
      (goto-char (point-min))
      (forward-line (/ lines 2))
      (search-forward "paragraph")
      (push (djot-modern-benchmark--time
             (lambda ()
               (insert "x")
               (font-lock-ensure (line-beginning-position) (line-end-position)))) results)
      ;; Inserting a closing fence near the end of a document with an unclosed
      ;; opener can legitimately invalidate almost the entire document.
      (goto-char (point-min))
      (insert "````\n")
      (font-lock-ensure)
      (goto-char (point-max))
      (push (djot-modern-benchmark--time
             (lambda () (insert "````\n") (font-lock-ensure))) results)
      (goto-char (point-min))
      (delete-region (point) (+ (point) 5))
      (goto-char (point-max))
      (delete-region (- (point) 5) (point))
      (font-lock-ensure)
      (goto-char (point-min))
      (forward-line (/ lines 2))
      (search-forward "| a | b |")
      (end-of-line)
      (push (djot-modern-benchmark--time
             (lambda ()
               (insert "\n| c | d |")
               (font-lock-ensure (line-beginning-position 0)
                                 (line-end-position 2)))) results)
      (djot-modern-mode -1)
      (nreverse results))))

(let* ((runs (string-to-number (or (getenv "DJOT_BENCH_RUNS") "3")))
       (gc-cons-threshold (* 16 1024 1024))
       (gc-cons-percentage 0.1))
  (unless (> runs 0) (error "DJOT_BENCH_RUNS must be positive"))
  (princ (format "%s\nGrammar ABI: %s; directory: %s\nGC threshold: %d; percentage: %s; runs: %d\n"
                 (emacs-version) (treesit-language-abi-version 'djot)
                 (or (getenv "DJOT_GRAMMAR_DIR") "Emacs default search path")
                 gc-cons-threshold gc-cons-percentage runs))
  ;; Warm library/query paths; each measured run still uses a fresh buffer/parser.
  (djot-modern-benchmark--run 1000)
  (princ "lines operation median-ms worst-ms\n")
  (dolist (lines '(1000 10000 100000))
    (let (samples)
      (dotimes (_ runs)
        (garbage-collect)
        (push (djot-modern-benchmark--run lines) samples))
      (cl-loop for operation in '(initial inline-edit fence-close table-insert)
               for index from 0
               for times = (sort (mapcar (lambda (row) (nth index row)) samples) #'<)
               do (princ (format "%d %s %.3f %.3f\n" lines operation
                                 (* 500 (+ (nth (/ (1- runs) 2) times)
                                           (nth (/ runs 2) times)))
                                 (* 1000 (car (last times)))))))))

;;; benchmark.el ends here
