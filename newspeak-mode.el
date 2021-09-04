;;; newspeak-mode.el --- Major mode for the Newspeak programming language  -*- lexical-binding:t -*-

;; Author: Daniel Szmulewicz
;; Maintainer: Daniel Szmulewicz <daniel.szmulewicz@gmail.com>
;; Version: 1.0
;; © 2021 Daniel Szmulewicz

;;; Commentary:

;; Major mode for Newspeak (https://newspeaklanguage.org//)

;; Provides the following functionality:
;; - Syntax highlighting.

;;; Code:

(require 'rx)
(require 'smie)

;;; syntax table

(defconst newspeak-mode-syntax-table
  (let ((table (make-syntax-table)))
    (modify-syntax-entry ?\( "() 1" table)
    (modify-syntax-entry ?\) ")( 4" table)
    (modify-syntax-entry ?|  "." table) ; punctuation
    (modify-syntax-entry ?* ". 23" table) ; Comment
    (modify-syntax-entry ?' "\"" table) ; String
    (modify-syntax-entry ?# "'" table) ; Expression prefix
    (modify-syntax-entry ?: "_" table)  ; colon is part of symbol
    (modify-syntax-entry ?< "(>" table) ; Type-hint-open interferes with rainbow-delimiters mode for symbol >
    (modify-syntax-entry ?> ")<" table) ; Type-hint-close
    table)
  "Newspeak mode syntax table.")

;;;;; Customization

(defgroup newspeak-mode ()
  "Custom group for the Newspeak major mode"
  :group 'languages)


(defgroup newspeak-mode-faces nil
  "Special faces for Newspeak mode."
  :group 'newspeak-mode)

;;;;; font-lock
;;;;; syntax highlighting

(defface newspeak--font-lock-type-face
  '((t (:inherit font-lock-type-face :bold t)))
  "Face description for types"
  :group 'newspeak-mode-faces)

(defface newspeak--font-lock-builtin-face
  '((t (:inherit font-lock-builtin-face)))
  "Face description for access modifiers"
  :group 'newspeak-mode-faces)

(defface newspeak--font-lock-constant-face
  '((t (:inherit font-lock-constant-face)))
  "Face description for reserved keywords"
  :group 'newspeak-mode-faces)

(defface newspeak--font-lock-keyword-face
  '((t (:inherit font-lock-keyword-face)))
  "Face description for block arguments"
  :group 'newspeak-mode-faces)

(defface newspeak--font-lock-warning-face
  '((t (:inherit font-lock-warning-face)))
  "Face description for `Newspeak3'"
  :group 'newspeak-mode-faces)

(defface newspeak--font-lock-variable-name-face
  '((t (:inherit font-lock-variable-name-face)))
  "Face description for slot assignments"
  :group 'newspeak-mode-faces)

(defface newspeak--font-lock-function-name-face
  '((t (:inherit font-lock-function-name-face)))
  "Face description for keyword and setter sends"
  :group 'newspeak-mode-faces)

(defface newspeak--font-lock-string-face
  '((t (:inherit font-lock-string-face)))
  "Face description for strings"
  :group 'newspeak-mode-faces)

(defface newspeak--font-lock-comment-face
  '((t (:inherit font-lock-comment-face)))
  "Face description for comments"
  :group 'newspeak-mode-faces)

(defvar newspeak-prettify-symbols-alist
  '(("^" . ?⇑)
    ("::=" . ?⇐)))

;; regexes definitions

(defconst newspeak--reserved-words (rx (or "yourself" "super" "outer" "true" "false" "nil" (seq symbol-start "self" symbol-end) (seq symbol-start "class" symbol-end))))
(defconst newspeak--access-modifiers (rx (or "private" "public" "protected")))
(defconst newspeak--block-arguments (rx word-start ":" (* alphanumeric)))
(defconst newspeak--symbol-literals (rx (seq ?# (* alphanumeric))))
(defconst newspeak--peculiar-construct (rx line-start "Newspeak3" line-end))
(defconst newspeak--class-names (rx word-start upper-case (* alphanumeric)))
(defconst newspeak--slots (rx (seq (or alpha ?_) (* (or alphanumeric ?_)) (+ whitespace) ?= (+ whitespace))))
(defconst newspeak--type-hints (rx (seq ?< (* alphanumeric) (zero-or-more (seq ?\[ (zero-or-more (seq (* alphanumeric) ?, whitespace)) (* alphanumeric) ?\])) ?>)))
(defconst newspeak--keyword-or-setter-send (rx (or alpha ?_) (* (or alphanumeric ?_)) (** 1 2 ?:)))

(defconst newspeak-font-lock
  `((,newspeak--reserved-words . 'newspeak--font-lock-constant-face)  ;; reserved words
    (,newspeak--access-modifiers . 'newspeak--font-lock-builtin-face) ;; access modifiers
    (,newspeak--block-arguments . 'newspeak--font-lock-keyword-face)  ;; block arguments
    (,newspeak--symbol-literals . 'newspeak--font-lock-keyword-face)  ;; symbol literals
    (,newspeak--peculiar-construct . 'newspeak--font-lock-warning-face)     ;; peculiar construct
    (,newspeak--class-names . 'newspeak--font-lock-type-face) ;; class names
    (,newspeak--slots . 'newspeak--font-lock-variable-name-face)     ;; slots
    (,newspeak--type-hints . 'newspeak--font-lock-type-face)     ;; type hints
    (,newspeak--keyword-or-setter-send . 'newspeak--font-lock-function-name-face)))     ;; keyword send and setter send

;;;;

(defcustom newspeak--indent-amount 2
  "'Tab size'; used for simple indentation alignment."
  :type 'integer)

;;;; SMIE
;;;; https://www.gnu.org/software/emacs/manual/html_node/elisp/SMIE.html

(defvar newspeak--smie-grammar
  (smie-prec2->grammar
   (smie-bnf->prec2
    '((id)
      (exp (id)
	   ("|-open" exp "|")
	   ("(" exp ")")
	   ("<" exp ">")
	   ("[" exp "]")
	   ("^" exp)
	   ("modifier" id "=" exp)))
    '((assoc ":"))
    '((assoc ".") (assoc "^")))))

(defun newspeak--smie-rules (method arg)
  "METHOD and ARG is rad."
  (message (format  "method: %s arg: %s hanging?: %s first?: %s" method arg (smie-rule-hanging-p) (smie-rule-bolp)))
  (pcase (cons method arg)
    (`(:before . "=") (cond
		       ((smie-rule-prev-p "method") newspeak--indent-amount)
		       (t 0)))
    (`(:after . "=") (smie-rule-separator method))
    (`(:before . "class") 0)
    (`(:before . "|-open") 0)
    (`(:before . "(") (cond
		       ((looking-at "class") 0)
		       (t newspeak--indent-amount)))
    (`(:after . "(") 0)
    (`(:after . ")") 0)
    (`(:before . "[") newspeak--indent-amount)
    (`(:before . ".") 0)
    (`(:after . ".") 0)
    (`(:list-intro . " ") 0)
    (_ newspeak--indent-amount)))

;; (defvar newspeaks--keywords-regexp
;;   (regexp-opt '("|" "class")))

(defun newspeak--smie-forward-token ()
  "Skip token forward and return it, along with its levels."
  (let ((tok (smie-default-forward-token)))
    (cond
     ((eq ?| tok) "|-open")
     (t tok))))

(defun newspeak--smie-backward-token ()
  "Skip token backward and return it, along with its levels."
  (let ((tok (smie-default-backward-token)))
    (cond
     ((member tok '("public" "private" "protected")) "modifier")
     ((eq ?| tok) "|")
     (t tok))))

;;;;

(defgroup newspeak-mode nil
  "Major mode for the Newspeak language"
  :prefix "newspeak-mode-"
  :group 'languages)

;;;###autoload
(add-to-list 'auto-mode-alist `(,(rx ".ns" eos) . newspeak-mode))

;;;###autoload
(define-derived-mode newspeak-mode prog-mode "1984"
  "Major mode for editing Newspeak files."
  (setq-local font-lock-defaults '(newspeak-font-lock))
  (setq-local font-lock-string-face 'newspeak--font-lock-string-face)
  (setq-local font-lock-comment-face 'newspeak--font-lock-comment-face)
  (setq-local prettify-symbols-alist newspeak-prettify-symbols-alist)
  (setq-local comment-start "(*")
  (setq-local comment-end "*)")
  (smie-setup newspeak--smie-grammar #'newspeak--smie-rules
	      :forward-token #'newspeak--smie-forward-token
	      :backward-token #'newspeak--smie-backward-token))

(provide 'newspeak-mode)

;;; newspeak-mode.el ends here
