;;; djot-modern.el --- Modern presentation for Djot -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jay Bonthius
;; Copyright (C) 2022-2026 Free Software Foundation, Inc.
;; Author: Jay Bonthius
;; Version: 0.2.0
;; Package-Requires: ((emacs "30.1") (djot-mode "0.1.0"))
;; URL: https://github.com/jaybonthius/djot-modern.el
;; Keywords: text, faces
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Optional typography for `djot-mode'.  Enable locally with
;; `djot-modern-mode', through `djot-mode-hook', or explicitly enable
;; `global-djot-modern-mode'.  No automatic global activation occurs.
;; Parsing, concealment, links, native source highlighting and editing
;; belong to djot-mode and continue working when this mode is disabled.
;;
;; Thin table rules (inverse-video stretch spaces and compressed rule
;; rows), block fringe bitmaps and opt-in activation follow Daniel
;; Mendler's org-modern.el (GPL-3.0-or-later).  Unlike org-modern's Org
;; font-lock integration, this package uses the base mode's semantic
;; hook and its own removable overlays; it never replaces font-lock rules.

;;; Code:

(require 'cl-lib)
(require 'color)
(require 'face-remap)
(require 'subr-x)
(require 'djot-mode)

(declare-function fringe-bitmap-p "fringe" (bitmap))
(declare-function define-fringe-bitmap "fringe" (bitmap bits &optional height width align))

(defgroup djot-modern nil
  "Modern presentation for Djot."
  :group 'djot :group 'faces :prefix "djot-modern-")

(defcustom djot-modern-prose-face 'variable-pitch
  "Face for body text, or nil to preserve the buffer's body font.
Technical text always uses `djot-modern-fixed-pitch'.  No font family
is chosen by this package.  Customize `variable-pitch' and `fixed-pitch'
in your theme or init.  Re-enable the mode after changing options."
  :type '(choice (const nil) face) :group 'djot-modern)
(defcustom djot-modern-line-spacing 0.15
  "Extra line spacing, or nil to retain the existing buffer setting."
  :type '(choice (const nil) number) :group 'djot-modern)
(defcustom djot-modern-headings t
  "Style headings with level-specific theme faces and scales."
  :type 'boolean :group 'djot-modern)
(defcustom djot-modern-heading-stars '("◉" "○" "◈" "◇" "✳" "·")
  "Heading glyphs, from level one; deeper levels use the last glyph.
Nil retains the source markers."
  :type '(repeat string) :group 'djot-modern)
(defcustom djot-modern-lists t
  "Style list markers and task boxes."
  :type 'boolean :group 'djot-modern)
(defcustom djot-modern-list '((?- . "–") (?+ . "◦") (?* . "•"))
  "Replacement glyphs for unordered list markers."
  :type '(alist :key-type character :value-type string) :group 'djot-modern)
(defcustom djot-modern-checkbox '((checked . "☑") (unchecked . "□"))
  "Replacement glyphs for task checkboxes."
  :type '(alist :key-type symbol :value-type string) :group 'djot-modern)
(defcustom djot-modern-blocks t
  "Style code, raw blocks, quotes, divs and thematic breaks."
  :type 'boolean :group 'djot-modern)
(defcustom djot-modern-block-fringe t
  "Draw block borders in graphical frame fringes.
Existing line or wrap prefixes take precedence over these decorations."
  :type 'boolean :group 'djot-modern)
(defcustom djot-modern-tables t
  "Display tables with aligned columns, padding and thin rules.
This never changes table source.  Use the base mode's alignment command
to align the source itself.  Terminal frames retain source table layout."
  :type 'boolean :group 'djot-modern)
(defcustom djot-modern-table-padding 1.0
  "Horizontal cell padding as a multiple of the fixed font width."
  :type 'number :group 'djot-modern)
(defcustom djot-modern-table-vertical 1
  "Width of graphical vertical table rules in pixels."
  :type 'natnum :group 'djot-modern)
(defcustom djot-modern-table-horizontal 0.15
  "Height of graphical table separator rows relative to normal text."
  :type 'float :group 'djot-modern)
(defcustom djot-modern-inline t
  "Style attribute labels and position subscript and superscript text.
Semantic emphasis and links are styled by djot-mode, not this option."
  :type 'boolean :group 'djot-modern)
(defcustom djot-modern-replace-markers t
  "Use display replacements for structural markers.
The explicit `djot-show-source' command also suppresses replacements.
Moving point never reveals markers automatically."
  :type 'boolean :group 'djot-modern)

(defface djot-modern-heading-1 '((t :inherit djot-heading-1 :height 1.35 :weight bold))
  "Level one heading; inherits the theme's first outline color." :group 'djot-modern)
(defface djot-modern-heading-2 '((t :inherit djot-heading-2 :height 1.2 :weight bold))
  "Level two heading." :group 'djot-modern)
(defface djot-modern-heading-3 '((t :inherit djot-heading-3 :height 1.1 :weight bold))
  "Level three heading." :group 'djot-modern)
(defface djot-modern-heading-4 '((t :inherit djot-heading-4 :weight bold))
  "Level four heading." :group 'djot-modern)
(defface djot-modern-heading-5 '((t :inherit djot-heading-5 :weight bold))
  "Level five heading." :group 'djot-modern)
(defface djot-modern-heading-6 '((t :inherit djot-heading-6 :weight bold))
  "Level six and deeper heading." :group 'djot-modern)
(defface djot-modern-fixed-pitch '((t :inherit fixed-pitch))
  "Technical text; deliberately has no token foreground override." :group 'djot-modern)
(defface djot-modern-symbol '((t :inherit (fixed-pitch shadow)))
  "Structural glyphs." :group 'djot-modern)
(defface djot-modern-label '((t :inherit (shadow fixed-pitch) :height 0.85 :box (:line-width -1)))
  "Compact language, div and attribute labels." :group 'djot-modern)
(defface djot-modern-quote '((t :slant italic))
  "Quoted prose; retains the body family and base quote color." :group 'djot-modern)
(defface djot-modern-code '((t :inherit fixed-pitch :extend t))
  "Code blocks; customize the background without overriding token colors." :group 'djot-modern)
(defface djot-modern-table '((t :inherit fixed-pitch))
  "Table cells." :group 'djot-modern)
(defface djot-modern-table-rule '((t :inherit shadow))
  "Thin table rules." :group 'djot-modern)
(defface djot-modern-checked '((t :inherit (fixed-pitch success)))
  "Completed task glyph." :group 'djot-modern)

(defvar-local djot-modern--remappings nil)
(defvar-local djot-modern--spacing nil)
(defvar-local djot-modern--metrics nil)
(defvar-local djot-modern--block-background nil)
(defvar djot-modern-mode)
(defvar djot-modern--beg)
(defvar djot-modern--end)
(defvar djot-modern--window nil
  "Window owning dynamically measured table decorations, or nil.")

(defun djot-modern--clear (beg end &optional all)
  "Clear our overlays in BEG END, preserving outside portions.
With ALL, remove intersecting decorations without splitting them."
  (dolist (overlay (overlays-in beg end))
    (when (and (overlay-get overlay 'djot-modern)
               (or all (not (overlay-get overlay 'display))
                   (and (>= (overlay-start overlay) beg)
                        (<= (overlay-end overlay) end))))
      (unless all
        (when (< (overlay-start overlay) beg)
          (move-overlay (copy-overlay overlay) (overlay-start overlay) beg))
        (when (> (overlay-end overlay) end)
          (move-overlay (copy-overlay overlay) end (overlay-end overlay))))
      (delete-overlay overlay))))

(defun djot-modern--foreign-property-p (beg end property)
  "Check for another package's PROPERTY between BEG and END."
  (or (text-property-not-all beg end property nil)
      (cl-some (lambda (ov)
                 (and (not (overlay-get ov 'djot-modern))
                      (overlay-get ov property)))
               (overlays-in beg end))))

(defun djot-modern--overlay (beg end &rest properties)
  "Decorate BEG END with PROPERTIES, clipped to the fontification range.
Display replacements are atomic and never override foreign displays."
  (let ((display (plist-get properties 'display)))
    (when (and (< beg end)
               (or (not display)
                   (and (<= djot-modern--beg beg) (<= end djot-modern--end)
                        (not (djot-modern--foreign-property-p beg end 'display)))))
      (setq beg (max beg djot-modern--beg) end (min end djot-modern--end))
      (when (< beg end)
        (let ((overlay (make-overlay beg end nil t nil)))
          (overlay-put overlay 'djot-modern t)
          (when djot-modern--window
            (overlay-put overlay 'window djot-modern--window))
          (overlay-put overlay 'evaporate t)
          ;; Native code and semantic text properties supply foregrounds.
          ;; Secondary priority lets explicit foreign overlays win.
          (overlay-put overlay 'priority '(nil . 5))
          (while properties
            (overlay-put overlay (pop properties) (pop properties)))
          overlay)))))

(defun djot-modern--face (node face)
  "Apply FACE to NODE within the current fontification range."
  (when node
    (djot-modern--overlay (treesit-node-start node) (treesit-node-end node)
                          'face face)))

(defun djot-modern--replace (node display &optional face)
  "Replace NODE's non-whitespace marker with DISPLAY and optional FACE."
  (when (and node display djot-modern-replace-markers (not djot-source-visible))
    (save-excursion
      (goto-char (treesit-node-start node))
      (skip-chars-forward " \t" (treesit-node-end node))
      (let ((beg (point)))
        (goto-char (treesit-node-end node))
        (skip-chars-backward " \t\n\r" beg)
        (djot-modern--overlay beg (point) 'display display
                              'face (or face 'djot-modern-symbol))))))

(defun djot-modern--fringe (node)
  "Draw an org-modern-style fringe border alongside NODE."
  (when (and djot-modern-block-fringe (display-graphic-p))
    (unless (fringe-bitmap-p 'djot-modern--inner)
      (define-fringe-bitmap 'djot-modern--inner [128] nil 8 '(top t))
      (define-fringe-bitmap 'djot-modern--begin
        (vconcat [0 0 0 0 0 255] (make-vector 122 128)) nil 8 'top)
      (define-fringe-bitmap 'djot-modern--end
        (vconcat (make-vector 122 128) [255 0 0 0 0 0]) nil 8 'bottom))
    (save-excursion
      (goto-char (treesit-node-start node))
      (let ((first (line-beginning-position))
            (last (save-excursion
                    (goto-char (1- (treesit-node-end node)))
                    (line-beginning-position))))
        (goto-char (max first (save-excursion
                               (goto-char djot-modern--beg)
                               (line-beginning-position))))
        (while (<= (point) last)
          (let* ((beg (point)) (end (min (point-max) (1+ (line-end-position))))
                 (bitmap (cond ((= beg first) 'djot-modern--begin)
                               ((= beg last) 'djot-modern--end)
                               (t 'djot-modern--inner)))
                 (prefix (propertize " " 'display
                                     `(left-fringe ,bitmap djot-modern-symbol))))
            (unless (or (djot-modern--foreign-property-p beg end 'line-prefix)
                        (djot-modern--foreign-property-p beg end 'wrap-prefix))
              (djot-modern--overlay beg end 'line-prefix prefix 'wrap-prefix prefix)))
          (if (= (forward-line 1) 0) nil (goto-char (1+ last))))))))

(defun djot-modern--heading (node)
  "Style the heading NODE and its continuation markers."
  (let* ((marker (treesit-node-child-by-field-name node "marker"))
         (level (length (string-trim (treesit-node-text marker t))))
         (face (intern (format "djot-modern-heading-%d" (min 6 level))))
         (content (treesit-node-child-by-field-name node "content")))
    (djot-modern--face content face)
    (when djot-modern-heading-stars
      (let ((glyph (nth (min (1- level) (1- (length djot-modern-heading-stars)))
                        djot-modern-heading-stars)))
        (djot-modern--replace marker glyph face)
        (dolist (child (djot-node-children content))
          (when (equal (treesit-node-type child) "marker")
            (djot-modern--replace child glyph face)))))))

(defun djot-modern--label (node)
  "Style NODE as a compact label, retaining all attribute values."
  (djot-modern--face node 'djot-modern-label)
  ;; Only the braces of a parsed attribute become padding.  Its values,
  ;; comments, escaped characters and multiline structure remain intact.
  (when (and djot-modern-replace-markers (not djot-source-visible)
             (member (treesit-node-type node) '("inline_attribute" "block_attribute")))
    (let ((beg (treesit-node-start node))
          (end (save-excursion
                 (goto-char (treesit-node-end node))
                 (skip-chars-backward " \t\r\n" (treesit-node-start node))
                 (point))))
      (when (and (eq (char-after beg) ?{) (eq (char-before end) ?}))
        (djot-modern--overlay beg (1+ beg) 'display " ")
        (djot-modern--overlay (1- end) end 'display " ")))))

(defun djot-modern--cell-property (position property)
  "Return the effective non-modern PROPERTY at POSITION.
Follow Emacs overlay priority, falling back to the text property."
  (or (cl-loop for overlay in (overlays-at position t)
               unless (overlay-get overlay 'djot-modern)
               thereis (overlay-get overlay property))
      (get-text-property position property)))

(defun djot-modern--cell-text (beg end)
  "Return the displayed text of a table cell between BEG and END.
Copy effective foreign replacement displays and invisibility into the
measurement string, clipped to the cell.  Never copy modern layout
padding/rules or modify another package's overlays or text properties."
  (let ((text (buffer-substring beg end)) (position beg))
    (while (< position end)
      (let* ((next (min end (next-overlay-change position)
                        (next-single-property-change position 'display nil end)
                        (next-single-property-change position 'invisible nil end)))
             (display (djot-modern--cell-property position 'display))
             (invisible (djot-modern--cell-property position 'invisible)))
        (put-text-property (- position beg) (- next beg) 'display display text)
        (put-text-property (- position beg) (- next beg) 'invisible
                           (and (invisible-p invisible) t) text)
        (setq position next)))
    ;; string-pixel-width uses a temporary buffer, so make the technical
    ;; family explicit rather than depending on its default face remap.
    (add-face-text-property 0 (length text) 'djot-modern-table t text)
    text))

(defun djot-modern--text-width (text)
  "Return the pixel width of displayed TEXT in a graphical frame."
  (string-pixel-width text))

(defun djot-modern--table-pipes (row)
  "Return direct pipe delimiter nodes in ROW, excluding literal cell pipes."
  (cl-loop for i below (treesit-node-child-count row)
           for child = (treesit-node-child row i)
           when (equal (treesit-node-type child) "|") collect child))

(defun djot-modern--table-cells (row)
  "Return cell bounds between semantic pipe tokens in ROW.
An empty cell has equal bounds and need not have a named syntax node."
  (cl-loop for tail on (djot-modern--table-pipes row) while (cdr tail)
           collect (cons (treesit-node-end (car tail))
                         (treesit-node-start (cadr tail)))))

(defun djot-modern--table (node)
  "Style NODE and measure its geometry independently in each live window.
Pixel decorations are window-local: a differently sized frame must never
reuse another frame's absolute padding.  Undisplayed buffers need no layout."
  (djot-modern--face node 'djot-modern-table)
  (when (and djot-modern-replace-markers (not djot-source-visible))
    (dolist (window (get-buffer-window-list (current-buffer) nil t))
      (when (display-graphic-p (window-frame window))
        (with-selected-window window
          (let ((djot-modern--window window))
            (djot-modern--table-layout node)))))))

(defun djot-modern--table-layout (node)
  "Lay out NODE for the selected window using parser-provided cell bounds."
  (let* ((rows (cl-remove-if-not
                (lambda (n) (member (treesit-node-type n)
                                    '("table_row" "table_header" "table_separator")))
                (djot-node-children node)))
         (widths (make-vector (apply #'max 0 (mapcar (lambda (n)
                                                       (length (djot-modern--table-cells n))) rows)) 0))
         (unit (djot-modern--text-width (propertize " " 'face 'djot-modern-table)))
         (pad (* djot-modern-table-padding unit))
         (rule djot-modern-table-vertical)
         (rule-face '(:inherit djot-modern-table-rule :inverse-video t))
         alignments)
    (dolist (row rows)
      (unless (equal (treesit-node-type row) "table_separator")
        (cl-loop for cell in (djot-modern--table-cells row) for col from 0 do
                 (let* ((text (string-trim (djot-modern--cell-text (car cell) (cdr cell))))
                        (width (djot-modern--text-width text)))
                   (aset widths col (max (aref widths col) width))))))
    (cl-loop for tail on rows for row = (car tail) do
             (when-let* ((separator (if (equal (treesit-node-type row) "table_separator") row
                                      (when (and (cadr tail)
						 (equal (treesit-node-type (cadr tail)) "table_separator"))
					(cadr tail)))))
               (setq alignments
                     (mapcar (lambda (cell)
                               (let ((text (treesit-node-text cell t)))
				 (cond ((and (string-prefix-p ":" text) (string-suffix-p ":" text)) 'center)
                                       ((string-suffix-p ":" text) 'right)
                                       (t 'left))))
                             (djot-node-children separator))))
             (let* ((separator (equal (treesit-node-type row) "table_separator"))
		    (cells (djot-modern--table-cells row))
		    (pipes (djot-modern--table-pipes row))
		    (x (save-excursion
			 (goto-char (treesit-node-start row))
			 (djot-modern--text-width
			  (propertize (buffer-substring-no-properties (line-beginning-position) (point))
                                      'face 'djot-modern-table)))))
               (when separator
		 (djot-modern--overlay (treesit-node-start row) (treesit-node-end row)
                                       'face `(:height ,djot-modern-table-horizontal)))
               (cl-loop for pipe in pipes for col from 0 do
			(djot-modern--overlay
			 (treesit-node-start pipe) (treesit-node-end pipe)
			 'before-string (propertize " " 'display `(space :align-to (,x))
                                                    'face (when separator `(:height ,djot-modern-table-horizontal)))
			 'display `(space :width (,rule))
			 'face (if separator (append `(:height ,djot-modern-table-horizontal) rule-face) rule-face))
			(when (< col (length widths))
			  (let* ((cell (nth col cells))
				 (beg (if cell (car cell) (treesit-node-end pipe)))
				 (end (if cell (cdr cell) beg))
				 (next-x (+ x rule pad (aref widths col) pad)))
			    (when separator
                              (djot-modern--overlay
                               beg end 'display `(space :align-to (,next-x))
                               'face `(:height ,djot-modern-table-horizontal
					       :inherit djot-modern-table-rule :overline t)))
			    (unless separator
                              ;; Source cell whitespace is the padding carrier.
                              ;; With no whitespace, a before-string adds padding
                              ;; without replacing or reparenting any cell text.
                              (save-excursion
				(goto-char beg)
				(skip-chars-forward " \t" end)
				(let ((trim-beg (point)))
				  (goto-char end)
				  (skip-chars-backward " \t" trim-beg)
				  (let* ((trim-end (point))
					 (width (djot-modern--text-width (djot-modern--cell-text trim-beg trim-end)))
					 (extra (max 0 (- (aref widths col) width)))
					 (left-pad (+ pad (pcase (nth col alignments)
							    ('right extra) ('center (/ extra 2)) (_ 0))))
					 (padding (propertize " " 'display `(space :width (,left-pad)))))
				    (if (< beg trim-beg)
					(djot-modern--overlay beg trim-beg 'display `(space :width (,left-pad)))
                                      (when (< beg end)
					(djot-modern--overlay beg (1+ beg) 'before-string padding)))
				    (when (< trim-end end)
                                      (djot-modern--overlay trim-end end 'display ""))))))
			    (setq x next-x))))))))

(defun djot-modern--quoted-p (node)
  "Return non-nil when NODE is inside a block quote."
  (let ((parent (treesit-node-parent node)))
    (while (and parent (not (equal (treesit-node-type parent) "block_quote")))
      (setq parent (treesit-node-parent parent)))
    parent))

(defun djot-modern--decorate (node)
  "Apply presentation to valid semantic NODE."
  (when (djot-node-valid-p node)
    (let ((type (treesit-node-type node)))
      (cond
       ((equal type "heading")
        (when djot-modern-headings (djot-modern--heading node)))
       ((member type '("code_block" "raw_block" "frontmatter"))
        (djot-modern--face node 'djot-modern-code)
        (when djot-modern-blocks
          (when djot-modern--block-background
            (let ((overlay (djot-modern--overlay
                            (treesit-node-start node) (treesit-node-end node)
                            'face `(:background ,djot-modern--block-background :extend t))))
              (when overlay (overlay-put overlay 'priority '(nil . -5)))))
          (djot-modern--fringe node)))
       ((member type '("verbatim" "raw_inline" "math"))
        (djot-modern--face node 'djot-modern-fixed-pitch))
       ((equal type "block_quote")
        (when djot-modern-blocks (djot-modern--fringe node)))
       ((equal type "paragraph")
        (when (and djot-modern-blocks (djot-modern--quoted-p node))
          (djot-modern--face node 'djot-modern-quote)))
       ((equal type "div")
        (when djot-modern-blocks (djot-modern--fringe node)))
       ((equal type "block_quote_marker")
        (when djot-modern-blocks (djot-modern--replace node "│")))
       ((member type '("code_block_marker_begin" "raw_block_marker_begin" "div_marker_begin"))
        (when (and djot-modern-blocks (djot-node-valid-p (treesit-node-parent node)))
          (djot-modern--replace node "▸")))
       ((member type '("code_block_marker_end" "raw_block_marker_end" "div_marker_end"))
        (when (and djot-modern-blocks (djot-node-valid-p (treesit-node-parent node)))
          (djot-modern--replace node "▰")))
       ((member type '("language" "class_name"))
        (when djot-modern-blocks (djot-modern--label node)))
       ((member type '("inline_attribute" "block_attribute"))
        (when djot-modern-inline (djot-modern--label node)))
       ((equal type "table") (when djot-modern-tables (djot-modern--table node)))
       ((equal type "table_header")
        (when djot-modern-tables (djot-modern--face node 'bold)))
       ((equal type "table_caption")
        (when djot-modern-tables
          (djot-modern--face node (delq nil (list 'italic djot-modern-prose-face)))))
       ((member type '("superscript" "subscript"))
        (when (and djot-modern-inline (not djot-source-visible))
          (let ((content (treesit-node-child-by-field-name node "content")))
            (when content
              (djot-modern--overlay (treesit-node-start content) (treesit-node-end content)
                                    'display `((height 0.8) (raise ,(if (equal type "superscript") 0.3 -0.2))))))))
       ((member type '("list_marker_dash" "list_marker_plus" "list_marker_star"))
        (when djot-modern-lists
          (djot-modern--replace node (alist-get (string-to-char (string-trim (treesit-node-text node t)))
                                                 djot-modern-list))))
       ((equal type "list_marker_task")
        (when djot-modern-lists
          (let* ((check (treesit-node-child-by-field-name node "checkmark"))
                 (state (intern (treesit-node-type check))))
            (djot-modern--replace node (alist-get state djot-modern-checkbox)
                                  (if (eq state 'checked) 'djot-modern-checked 'djot-modern-symbol)))))
       ((equal type "thematic_break")
        (when djot-modern-blocks
          (djot-modern--replace node '(space :width 30) '(:inherit shadow :strike-through t))))))))

(defun djot-modern--fontify (beg end)
  "Refresh this mode's presentation after base fontification in BEG END."
  (when djot-modern-mode
    (let ((djot-modern--beg beg) (djot-modern--end end))
      (save-excursion
        (save-match-data
          (djot-modern--clear beg end)
          (djot-map-nodes #'djot-modern--decorate beg end))))))

(defun djot-modern--after-change (beg end _old-length)
  "Invalidate enclosing table layout after a source edit in BEG END."
  (when djot-modern-tables
    (when-let* ((table (or (djot-node-at beg "table") (djot-node-at end "table"))))
      (font-lock-flush (treesit-node-start table) (treesit-node-end table)))))

(defun djot-modern--window-metrics (window)
  "Return the frame-dependent layout signature for WINDOW."
  (with-selected-window window
    (list window (display-graphic-p) (face-font 'fixed-pitch)
          (face-font 'djot-modern-table) (face-font 'default) (frame-char-height)
          (face-attribute 'djot-modern-table-rule :foreground nil t)
          (face-background 'default nil t) (face-foreground 'default nil t))))

(defun djot-modern--pre-redisplay (window)
  "Refresh frame-dependent layout before redisplaying WINDOW.
Track every view so selecting a frame cannot alternate shared geometry.
Also detect first display, new views, closed windows and font/theme changes."
  (let* ((windows (get-buffer-window-list (current-buffer) nil t))
         ;; Activation has no WINDOW argument, but may already have a view.
         (window (or window (car windows)))
         (metrics (mapcar #'djot-modern--window-metrics windows)))
    (unless (equal metrics djot-modern--metrics)
      (setq djot-modern--metrics metrics)
      (when (and (window-live-p window) (display-graphic-p (window-frame window)))
        (with-selected-window window
          (setq djot-modern--block-background
                (let ((bg (color-name-to-rgb (face-background 'default nil t)))
                      (fg (color-name-to-rgb (face-foreground 'default nil t))))
                  (when (and bg fg)
                    (apply #'color-rgb-to-hex
                           (cl-mapcar (lambda (b f) (+ (* 0.96 b) (* 0.04 f))) bg fg)))))))
      (font-lock-flush))))

(defun djot-modern--font-lock-change ()
  "Follow explicit font-lock activation or deactivation in this buffer."
  (when djot-modern-mode
    (save-restriction
      (widen)
      (if font-lock-mode (djot-refresh)
        (djot-modern--clear (point-min) (point-max) t)))))

(defun djot-modern--disable ()
  "Remove all local presentation without touching base-mode decorations."
  (remove-hook 'djot-after-fontify-hook #'djot-modern--fontify t)
  (remove-hook 'after-change-functions #'djot-modern--after-change t)
  (remove-hook 'pre-redisplay-functions #'djot-modern--pre-redisplay t)
  (remove-hook 'change-major-mode-hook #'djot-modern--disable t)
  (remove-hook 'font-lock-mode-hook #'djot-modern--font-lock-change t)
  (save-restriction
    (widen)
    (djot-modern--clear (point-min) (point-max) t))
  (mapc #'face-remap-remove-relative djot-modern--remappings)
  (setq djot-modern--remappings nil djot-modern--metrics nil)
  (when djot-modern--spacing
    (when (equal line-spacing (nth 2 djot-modern--spacing))
      (if (car djot-modern--spacing)
          (setq-local line-spacing (cadr djot-modern--spacing))
        (kill-local-variable 'line-spacing)))
    (setq djot-modern--spacing nil)))

;;;###autoload
(define-minor-mode djot-modern-mode
  "Optional modern typography for `djot-mode'.
No buffer text, semantic font-lock rules, concealment or editing commands
are changed.  Use `djot-show-source' to explicitly inspect raw syntax."
  :lighter " DjM" :group 'djot-modern
  (djot-modern--disable)
  (when djot-modern-mode
    (unless (derived-mode-p 'djot-mode)
      (setq djot-modern-mode nil)
      (user-error "Enable djot-mode before djot-modern-mode"))
    (when djot-modern-prose-face
      (push (face-remap-add-relative 'default djot-modern-prose-face)
            djot-modern--remappings))
    (when djot-modern-line-spacing
      (setq djot-modern--spacing (list (local-variable-p 'line-spacing)
                                       line-spacing djot-modern-line-spacing))
      (setq-local line-spacing djot-modern-line-spacing))
    (add-hook 'djot-after-fontify-hook #'djot-modern--fontify nil t)
    (add-hook 'after-change-functions #'djot-modern--after-change nil t)
    (add-hook 'pre-redisplay-functions #'djot-modern--pre-redisplay nil t)
    (add-hook 'change-major-mode-hook #'djot-modern--disable nil t)
    (add-hook 'font-lock-mode-hook #'djot-modern--font-lock-change nil t)
    (djot-modern--pre-redisplay nil)
    (save-restriction
      (widen)
      (djot-refresh))))

(defun djot-modern--on ()
  "Enable modern presentation in a Djot buffer."
  (when (derived-mode-p 'djot-mode) (djot-modern-mode 1)))

;;;###autoload
(define-globalized-minor-mode global-djot-modern-mode
  djot-modern-mode djot-modern--on :group 'djot-modern)

(provide 'djot-modern)
;;; djot-modern.el ends here
