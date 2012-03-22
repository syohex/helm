;;; helm-mode.el --- Enable helm completion evrywhere.

;; Copyright (C) 2012 Thierry Volpiatto <thierry.volpiatto@gmail.com>

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Code:

(eval-when-compile (require 'cl))
(require 'helm)
(require 'helm-files)

;;; Helm `completing-read' replacement
;;
;;
(defun helm-comp-read-get-candidates (collection &optional test sort-fn alistp)
  "Convert COLLECTION to list removing elements that don't match TEST.
See `helm-comp-read' about supported COLLECTION arguments.

SORT-FN is a predicate to sort COLLECTION.

ALISTP when non--nil will not use `all-completions' to collect
candidates because it doesn't handle alists correctly for helm.
i.e In `all-completions' the keys \(cars of elements\)
are the possible completions. In helm we want to use the cdr instead
like \(display . real\).

e.g

\(setq A '((a . 1) (b . 2) (c . 3)))
==>((a . 1) (b . 2) (c . 3))
\(helm-comp-read \"test: \" A :alistp nil
                                  :exec-when-only-one t
                                  :initial-input \"a\")
==>\"a\"
\(helm-comp-read \"test: \" A :alistp t
                                  :exec-when-only-one t
                                  :initial-input \"1\")
==>\"1\"

See docstring of `all-completions' for more info.

If COLLECTION is an `obarray', a TEST should be needed. See `obarray'."
  (let ((cands
         (cond ((and (eq collection obarray) test)
                (all-completions "" collection test))
               ((and (vectorp collection) test)
                (loop for i across collection when (funcall test i) collect i))
               ((vectorp collection)
                (loop for i across collection collect i))
               ((and alistp test)
                (loop for i in collection when (funcall test i) collect i))
               ((and (symbolp collection) (boundp collection))
                (symbol-value collection))
               (alistp collection)
               ((and collection test)
                (all-completions "" collection test))
               (t (all-completions "" collection)))))
    (if sort-fn (sort cands sort-fn) cands)))

(defun helm-cr-default-transformer (candidates source)
  "Default filter candidate function for `helm-comp-read'."
  (loop for cand in candidates
        if (and (string= cand helm-pattern)
                (not (member helm-pattern
                             (or (cdr candidates)
                                 candidates))))
        collect (cons (concat (propertize
                               " " 'display
                               (propertize "[?]" 'face 'helm-ff-prefix))
                              cand)
                      cand)
        else collect cand))

(defun* helm-comp-read (prompt collection
                               &key
                               test
                               initial-input
                               default
                               preselect
                               (buffer "*Helm Completions*")
                               must-match
                               (requires-pattern 0)
                               (history nil)
                               input-history
                               (persistent-action nil)
                               (persistent-help "DoNothing")
                               (mode-line helm-mode-line-string)
                               (keymap helm-map)
                               (name "Helm Completions")
                               candidates-in-buffer
                               exec-when-only-one
                               (volatile t)
                               sort
                               (fc-transformer 'helm-cr-default-transformer)
                               (marked-candidates nil)
                               (alistp t))
  "Read a string in the minibuffer, with helm completion.

It is helm `completing-read' equivalent.

- PROMPT is the prompt name to use.

- COLLECTION can be a list, vector, obarray or hash-table.
  It can be also a function that receives three arguments:
  the values string, predicate and t. See `all-completions' for more details.

Keys description:

- TEST: A predicate called with one arg i.e candidate.

- INITIAL-INPUT: Same as input arg in `helm'.

- PRESELECT: See preselect arg of `helm'.

- DEFAULT: This option is used only for compatibility with regular
  Emacs `completing-read'.

- BUFFER: Name of helm-buffer.

- MUST-MATCH: Candidate selected must be one of COLLECTION.

- REQUIRES-PATTERN: Same as helm attribute, default is 0.

- HISTORY: A list containing specific history, default is nil.
  When it is non--nil, all elements of HISTORY are displayed in
  a special source before COLLECTION.

- INPUT-HISTORY: A symbol. the minibuffer input history will be
  stored there, if nil or not provided, `minibuffer-history'
  will be used instead.

- PERSISTENT-ACTION: A function called with one arg i.e candidate.

- PERSISTENT-HELP: A string to document PERSISTENT-ACTION.

- MODE-LINE: A string or list to display in mode line.
  (See `helm-mode-line-string')

- KEYMAP: A keymap to use in this `helm-comp-read'.
  (The keymap will be shared with history source)

- NAME: The name related to this local source.

- EXEC-WHEN-ONLY-ONE: Bound `helm-execute-action-at-once-if-one'
  to non--nil. (possibles values are t or nil).

- VOLATILE: Use volatile attribute \(enabled by default\).

- SORT: A predicate to give to `sort' e.g `string-lessp'.

- FC-TRANSFORMER: A `filtered-candidate-transformer' function.

- MARKED-CANDIDATES: If non--nil return candidate or marked candidates as a list.

- ALISTP: \(default is non--nil\) See `helm-comp-read-get-candidates'.

- CANDIDATES-IN-BUFFER: when non--nil use a source build with
  `helm-candidates-in-buffer' which is much faster.
  Argument VOLATILE have no effect when CANDIDATES-IN-BUFFER is non--nil.

Any prefix args passed during `helm-comp-read' invocation will be recorded
in `helm-current-prefix-arg', otherwise if prefix args were given before
`helm-comp-read' invocation, the value of `current-prefix-arg' will be used.
That's mean you can pass prefix args before or after calling a command
that use `helm-comp-read' See `helm-M-x' for example."
  (when (get-buffer helm-action-buffer)
    (kill-buffer helm-action-buffer))
  (flet ((action-fn (candidate)
           (if marked-candidates
               (helm-marked-candidates)
               (identity candidate))))
    ;; Assume completion have been already required,
    ;; so always use 'confirm.
    (when (eq must-match 'confirm-after-completion)
      (setq must-match 'confirm))
    (let* ((minibuffer-completion-confirm must-match)
           (must-match-map (when must-match
                             (let ((map (make-sparse-keymap)))
                               (define-key map (kbd "RET")
                                 'helm-confirm-and-exit-minibuffer)
                               map)))
           (helm-map (if must-match-map
                         (make-composed-keymap
                          must-match-map (or keymap helm-map))
                         (or keymap helm-map)))
           (src-hist `((name . ,(format "%s History" name))
                       (candidates
                        . (lambda ()
                            (let ((all (helm-comp-read-get-candidates
                                        history nil nil ,alistp)))
                              (delete
                               ""
                               (helm-fast-remove-dups
                                (if (and default (not (string= default "")))
                                    (delq nil (cons default
                                                    (delete default all)))
                                    all)
                                :test 'equal)))))
                       (filtered-candidate-transformer
                        . (lambda (candidates sources)
                            (loop for i in candidates
                                  do (set-text-properties 0 (length i) nil i)
                                  collect i)))
                       (persistent-action . ,persistent-action)
                       (persistent-help . ,persistent-help)
                       (mode-line . ,mode-line)
                       (action . ,'action-fn)))
           (src `((name . ,name)
                  (candidates
                   . (lambda ()
                       (let ((cands (helm-comp-read-get-candidates
                                     collection test sort alistp)))
                         (unless (or (eq must-match t) (string= helm-pattern ""))
                           (setq cands (append (list helm-pattern) cands)))
                         (if (and default (not (string= default "")))
                             (delq nil (cons default (delete default cands)))
                             cands))))
                  (filtered-candidate-transformer ,fc-transformer)
                  (requires-pattern . ,requires-pattern)
                  (persistent-action . ,persistent-action)
                  (persistent-help . ,persistent-help)
                  (mode-line . ,mode-line)
                  (action . ,'action-fn)))
           (src-1 `((name . ,name)
                    (init
                     . (lambda ()
                         (let ((cands (helm-comp-read-get-candidates
                                       collection test sort alistp)))
                           (unless (or (eq must-match t) (string= helm-pattern ""))
                             (setq cands (append (list helm-pattern) cands)))
                           (with-current-buffer (helm-candidate-buffer 'global)
                             (loop for i in
                                   (if (and default (not (string= default "")))
                                       (delq nil (cons default (delete default cands)))
                                       cands)
                                   do (insert (concat i "\n")))))))
                    (candidates-in-buffer)
                    (filtered-candidate-transformer ,fc-transformer)
                    (requires-pattern . ,requires-pattern)
                    (persistent-action . ,persistent-action)
                    (persistent-help . ,persistent-help)
                    (mode-line . ,mode-line)
                    (action . ,'action-fn)))
           (src-list (list src-hist
                           (if candidates-in-buffer
                               src-1
                               (if volatile
                                   (append src '((volatile)))
                                   src))))
           (helm-execute-action-at-once-if-one exec-when-only-one))
      (or
       (helm
        :sources src-list
        :input initial-input
        :default default
        :preselect preselect
        :prompt prompt
        :resume 'noresume
        :keymap helm-map
        :history (and (symbolp input-history) input-history)
        :buffer buffer)
       (when (and (eq helm-exit-status 0)
                  (eq must-match 'confirm))
         ;; Return empty string only if it is the DEFAULT
         ;; value and helm-pattern is empty.
         ;; otherwise return helm-pattern
         (if (and (string= helm-pattern "") default)
             default (identity helm-pattern)))
       (unless (or (eq helm-exit-status 1)
                   must-match)  ; FIXME this should not be needed now.
         default)
       (keyboard-quit)))))

;; Generic completing-read
;;
;; Support also function as collection.
;; e.g M-x man is supported.
;; Support hash-table and vectors as collection.
;; NOTE:
;; Some crap emacs functions may not be supported
;; like ffap-alternate-file (bad use of completing-read)
;; and maybe others.
;; Provide a mode `helm-mode' which turn on
;; helm in all `completing-read' and `read-file-name' in Emacs.
;;
(defvar helm-completion-mode-string " Helm")

(defvar helm-completion-mode-quit-message
  "Helm completion disabled")

(defvar helm-completion-mode-start-message
  "Helm completion enabled")

;;; Specialized handlers
;;
;;
(defun helm-completing-read-symbols
    (prompt collection test require-match init
     hist default inherit-input-method name buffer)
  "Specialized function for fast symbols completion in `helm-mode'."
  (or
   (helm
    :sources `((name . ,name)
               (init . (lambda ()
                         (with-current-buffer (helm-candidate-buffer 'global)
                           (goto-char (point-min))
                           (when (and default (stringp default)
                                      ;; Some defaults args result as
                                      ;; (symbol-name nil) == "nil".
                                      ;; e.g debug-on-entry.
                                      (not (string= default "nil"))
                                      (not (string= default "")))
                             (insert (concat default "\n")))
                           (loop with all = (all-completions "" collection test)
                                 for sym in all
                                 unless (and default (eq sym default))
                                 do (insert (concat sym "\n"))))))
               (persistent-action . helm-lisp-completion-persistent-action)
               (persistent-help . "Show brief doc in mode-line")
               (candidates-in-buffer)
               (action . identity))
    :prompt prompt
    :buffer buffer
    :input init
    :history hist
    :resume 'noresume
    :default (or default ""))
   (keyboard-quit)))


;;; Generic completing read
;;
;;
(defun helm-completing-read-default-1
    (prompt collection test require-match
     init hist default inherit-input-method
     name buffer &optional cands-in-buffer exec-when-only-one)
  "Call `helm-comp-read' with same args as `completing-read'.
Extra optional arg CANDS-IN-BUFFER mean use `candidates-in-buffer'
method which is faster.
It should be used when candidate list don't need to rebuild dynamically."
  (let ((history (or (car-safe hist) hist)))
    (helm-comp-read
     prompt collection
     :test test
     :history history
     :input-history history
     :must-match require-match
     :alistp nil ; Be sure `all-completions' is used.
     :name name
     :requires-pattern (if (and (string= default "")
                                (or (eq require-match 'confirm)
                                    (eq require-match
                                        'confirm-after-completion)))
                           1 0)
     :candidates-in-buffer cands-in-buffer
     :exec-when-only-one exec-when-only-one
     :buffer buffer
     ;; If DEF is not provided, fallback to empty string
     ;; to avoid `thing-at-point' to be appended on top of list
     :default (or default "")
     ;; Use `regexp-quote' to fix initial input
     ;; with special characters (e.g nnimap+gmail:)
     :initial-input (and (stringp init) (regexp-quote init)))))

(defun helm-completing-read-with-cands-in-buffer
    (prompt collection test require-match
     init hist default inherit-input-method
     name buffer)
  "Same as `helm-completing-read-default-1' but use candidates-in-buffer."
  ;; Some commands like find-tag may use `read-file-name' from inside
  ;; the calculation of collection. in this case it clash with
  ;; candidates-in-buffer that reuse precedent data (files) which is wrong.
  ;; So (re)calculate collection outside of main helm-session.
  (let ((cands (all-completions "" collection)))
    (helm-completing-read-default-1 prompt cands test require-match
                                    init hist default inherit-input-method
                                    name buffer t)))

(defun* helm-completing-read-default
    (prompt collection &optional
            predicate require-match
            initial-input hist def
            inherit-input-method)
  "An helm replacement of `completing-read'.
This function should be used only as a `completing-read-function'.

Don't use it directly, use instead `helm-comp-read' in your programs.

See documentation of `completing-read' and `all-completions' for details."
  (declare (special helm-mode))
  (let* ((current-command this-command)
         (str-command     (symbol-name current-command))
         (buf-name        (format "*helm-mode-%s*" str-command))
         (entry           (assq current-command
                                helm-completing-read-handlers-alist))
         (def-com         (cdr-safe entry))
         (str-defcom      (and def-com (symbol-name def-com)))
         (def-args        (list prompt collection predicate require-match
                                initial-input hist def inherit-input-method))
         ;; Append the two extra args needed to set the buffer and source name
         ;; in helm specialized functions.
         (any-args        (append def-args (list str-command buf-name)))
         helm-completion-mode-start-message ; Be quiet
         helm-completion-mode-quit-message
         (minibuffer-completion-table collection)
         (minibuffer-completion-predicate predicate)
         ;; Be sure this pesty *completion* buffer doesn't popup.
         (minibuffer-setup-hook (remove 'minibuffer-completion-help
                                        minibuffer-setup-hook)))
    (when (eq def-com 'ido) (setq def-com 'ido-completing-read))
    (unless (or (not entry) def-com (eq collection 'read-file-name-internal))
      ;; An entry in *read-handlers-alist exists but have
      ;; a nil value, so we exit from here, disable `helm-mode'
      ;; and run the command again with it original behavior.
      ;; `helm-mode' will be restored on exit.
      (return-from helm-completing-read-default
        (unwind-protect
             (progn
               (helm-mode -1)
               (apply completing-read-function def-args))
          (helm-mode 1))))
    (setq def (if (and def (listp def)) (helm-comp-read "Use: " def) def))
    ;; If we use now `completing-read' we MUST turn off `helm-mode'
    ;; to avoid infinite recursion and CRASH. It will be reenabled on exit.
    (when (or (eq def-com 'completing-read)
              ;; All specialized functions are prefixed by "helm"
              (and (stringp str-defcom)
                   (not (string-match "^helm" str-defcom))))
      (helm-mode -1))
    (unwind-protect
         (cond (;; An helm specialized function exists, run it.
                (and def-com helm-mode)
                (apply def-com any-args))
               (;; Try to handle `ido-completing-read' everywhere.
                (and def-com (eq def-com 'ido-completing-read))
                (setcar (memq collection def-args)
                        (all-completions "" collection predicate))
                (apply def-com def-args))
               (;; User set explicitely `completing-read' or something similar
                ;; in *read-handlers-alist, use this with exactly the same
                ;; args as in `completing-read'.
                ;; If we are here `helm-mode' is now disabled.
                def-com
                (apply def-com def-args))
               (t ; Fall back to classic `helm-comp-read'.
                (helm-completing-read-default-1
                 prompt collection predicate require-match
                 initial-input hist def inherit-input-method
                 str-command buf-name)))
      (helm-mode 1)
      ;; When exiting minibuffer, `this-command' is set to
      ;; `helm-exit-minibuffer', which is unwanted when starting
      ;; on another `completing-read', so restore `this-command' to
      ;; initial value when exiting.
      (setq this-command current-command))))

(defun* helm-generic-read-file-name
    (prompt &optional dir default-filename mustmatch initial predicate)
  "An helm replacement of `read-file-name'."
  (declare (special helm-mode))
  (let* ((default (and default-filename
                       (if (listp default-filename)
                           (car default-filename)
                           default-filename)))
         (init (or default initial dir default-directory))
         (ini-input (and init (expand-file-name init)))
         (current-command this-command)
         (str-command (symbol-name current-command))
         (helm-file-completion-sources
          (cons str-command
                (remove str-command helm-file-completion-sources)))
         (buf-name (format "*helm-mode-%s*" str-command))
         (entry (assq current-command
                      helm-completing-read-handlers-alist))
         (def-com  (cdr-safe entry))
         (str-defcom (symbol-name def-com))
         (def-args (list prompt dir default-filename mustmatch initial predicate))
         ;; Append the two extra args needed to set the buffer and source name
         ;; in helm specialized functions.
         (any-args (append def-args (list str-command buf-name)))
         (ido-state ido-mode)
         helm-completion-mode-start-message ; Be quiet
         helm-completion-mode-quit-message  ; Same here
         fname)
    ;; Some functions that normally call `completing-read' can switch
    ;; brutally to `read-file-name' (e.g find-tag), in this case
    ;; the helm specialized function will fail because it is build
    ;; for `completing-read', so set it to 'incompatible to be sure
    ;; we switch to `helm-c-read-file-name' and don't try to call it
    ;; with wrong number of args.
    (when (and def-com (> (length (help-function-arglist def-com)) 8))
      (setq def-com 'incompatible))
    (when (eq def-com 'ido) (setq def-com 'ido-read-file-name))
    (unless (or (not entry) def-com)
      (return-from helm-generic-read-file-name
        (unwind-protect
             (progn
               (helm-mode -1)
               (apply read-file-name-function def-args))
          (helm-mode 1))))
    ;; If we use now `read-file-name' we MUST turn off `helm-mode'
    ;; to avoid infinite recursion and CRASH. It will be reenabled on exit.
    (when (or (eq def-com 'read-file-name)
              (eq def-com 'ido-read-file-name)
              (and (stringp str-defcom)
                   (not (string-match "^helm" str-defcom))))
      (helm-mode -1))
    (unwind-protect
         (setq fname
               (cond (;; A specialized function exists, run it
                      ;; with the two extra args specific to helm..
                      (and def-com helm-mode
                           (not (eq def-com 'ido-read-file-name))
                           (not (eq def-com 'incompatible)))
                      (apply def-com any-args))
                     (;; Def-com value is `ido-read-file-name'
                      ;; run it with default args.
                      (and def-com (eq def-com 'ido-read-file-name))
                      (ido-mode 1)
                      (apply def-com def-args))
                     (;; Def-com value is `read-file-name'
                      ;; run it with default args.
                      (eq def-com 'read-file-name)
                      (apply def-com def-args))
                     (t ; Fall back to classic `helm-c-read-file-name'.
                      (helm-c-read-file-name
                       prompt
                       :name str-command
                       :buffer buf-name
                       :initial-input (expand-file-name init dir)
                       :alistp nil
                       :must-match mustmatch
                       :test predicate))))
      (helm-mode 1)
      (ido-mode (if ido-state 1 -1))
      ;; Same comment as in `helm-completing-read-default'.
      (setq this-command current-command))
    fname))

;;;###autoload
(define-minor-mode helm-mode
    "Toggle generic helm completion.

All functions in Emacs that use `completing-read'
or `read-file-name' and friends will use helm interface
when this mode is turned on.
However you can modify this behavior for functions of your choice
with `helm-completing-read-handlers-alist'.

Called with a positive arg, turn on unconditionally, with a
negative arg turn off.
You can turn it on with `helm-mode'.

Some crap emacs functions may not be supported,
e.g `ffap-alternate-file' and maybe others
You can add such functions to `helm-completing-read-handlers-alist'
with a nil value.

Note: This mode will work only partially on Emacs23."
  :group 'helm
  :global t
  :lighter helm-completion-mode-string
  (declare (special completing-read-function))
  (if helm-mode
      (progn
        (setq completing-read-function 'helm-completing-read-default
              read-file-name-function  'helm-generic-read-file-name)
        (message helm-completion-mode-start-message))
      (setq completing-read-function (and (fboundp 'completing-read-default)
                                          'completing-read-default)
            read-file-name-function  (and (fboundp 'read-file-name-default)
                                          'read-file-name-default))
      (message helm-completion-mode-quit-message)))

(provide 'helm-mode)

;;; helm-mode.el ends here