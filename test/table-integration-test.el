;;; table-integration-test.el --- Composed editing and presentation -*- lexical-binding: t; -*-
(require 'djot-modern-test)

(ert-deftest djot-modern-table-align-does-not-count-modern-padding ()
  (should (fboundp 'djot-table-align))
  (djot-modern-test--buffer
      "| Name | Value |\n|------|------:|\n| [a](https://example.org/a/long/destination) | one |\n| `x|y` | two |\n"
    (goto-char (point-min))
    (djot-table-align)
    ;; Hidden URL source must not dictate the width of visible header cells.
    (save-excursion
      (goto-char (point-min))
      (should (< (- (line-end-position) (line-beginning-position)) 35)))
    (let ((aligned (buffer-substring-no-properties (point-min) (point-max))))
      (djot-modern-mode 1)
      (dotimes (_ 3)
        (djot-table-align)
        (djot-refresh)
        (should (equal aligned (buffer-substring-no-properties (point-min) (point-max)))))
      (djot-modern-mode -1)
      (djot-table-align)
      (should (equal aligned (buffer-substring-no-properties (point-min) (point-max))))
      (djot-show-source 1)
      (should (equal aligned (buffer-substring-no-properties (point-min) (point-max))))
      (djot-table-align)
      (let ((source-aligned (buffer-substring-no-properties (point-min) (point-max))))
        (djot-modern-mode 1)
        (djot-table-align)
        (should (equal source-aligned (buffer-substring-no-properties (point-min) (point-max))))))))

(ert-deftest djot-modern-table-empty-cell-semantic-regression ()
  ;; This is a hard dependency regression, not a source reparsing fallback.
  ;; The original grammar consumed || as part of the next table_cell.
  (dolist (row '("|a||c|" "||b|c|" "|a|b||" "||||"))
    (djot-modern-test--buffer (concat row "\n|:-|--:|:-:|\n|1|2|3|\n")
      (djot-modern-mode 1)
      (let ((header (djot-node-at 1 "table_header")))
        (should header)
        (should (= 4 (length (djot-modern--table-pipes header))))
        (should (= 3 (length (djot-modern--table-cells header)))))
      (goto-char 1)
      (djot-table-align)
      (let ((aligned (buffer-substring-no-properties (point-min) (point-max))))
        (djot-table-align)
        (should (equal aligned (buffer-substring-no-properties (point-min) (point-max))))))))

(provide 'table-integration-test)
;;; table-integration-test.el ends here
