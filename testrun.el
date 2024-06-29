;;; testrun.el --- helpers for running tests  -*- lexical-binding:t -*-
;;;
;;; Version: 1
;;;
;;; Commentary:

;;; Cater to the most common scenarios:
;;; - run a test at point
;;; - rerun the most recently run testing command
;;; - TODO select and rerun a recently run testing command
;;; - TODO jump to recently used tests
;;; - TODO run tests in current directory
;;; - TODO run tests in current project

;;; Code:

(require 'treesit)


;;;; Customization


(defcustom testrun-backends
  '((:mode go-ts-mode :backend testrun--go-backend)
    (:mode go-mode :backend testrun--go-backend))
  "A list of backends to use for running tests."
  :type '(sexp)
  :group 'languages)


;;;; Methods


;;;###autoload
(defun testrun-at-point ()
  "Run a test at point."
  (interactive)
  (let* ((b (testrun--pick-backend))
         (c (testrun--backend-test-command-at-point b)))
    (compile c)))


;;;; Golang


(defun testrun--go-backend ()
  "Supports testrun for Golang."
  (list :test-command-at-point #'testrun--go-test-command-at-point))


(defun testrun--go-recognize-test-chain ()
  "Recognize nesting levels of Go Test and t.Run sub-tests around point as a list."
  (let ((loop t)
        (acc nil)
        (n (treesit-node-at (point))))
    (while (and n loop)
      (let ((x (testrun--go-parse-func-test n)))
        (if x (progn (setq acc (cons x acc))
                     (setq loop nil))
          (let ((y (testrun--go-parse-t-run-node n)))
            (when y (setq acc (cons y acc))))))
      (setq n (treesit-node-parent n)))
    acc))


(defun testrun--go-parse-func-test (node)
  "Recognizes if the treesitter NODE is a test function."
  (pcase node
    ((and (pred treesit-node-p)
          (app treesit-node-type "function_declaration")
          (app treesit-node-children
               `(,_
                 ,x
                 ,(pred testrun--go-func-testing-parameter-list-p)
                 ,_)))
     (treesit-node-text x t))
    (_ nil)))


(defun testrun--go-func-testing-parameter-list-p (node)
  "Recognizes if the treesitter NODE is like (t *testing.T)."
  (pcase node
    ((and (pred treesit-node-p)
          (app treesit-node-type "parameter_list")
          (app treesit-node-children
               `(,_
                 ,(and (app treesit-node-type "parameter_declaration")
                       (app treesit-node-children
                            `(,_
                              ,(and (app treesit-node-type "pointer_type")
                                    (app treesit-node-children
                                         `(,(app treesit-node-text "*")
                                           ,(app treesit-node-children
                                                 `(,(app treesit-node-text "testing")
                                                   ,(app treesit-node-text ".")
                                                   ,(app treesit-node-text "T")))
                                           ))))))
                 ,_)))
     t)
    (_ nil)))


(defun testrun--go-func-testing-node-p (node)
  "Recognizes if the treesitter NODE is like func(t *testing.T) {..}."
  (pcase node
    ((and (pred treesit-node-p)
          (app treesit-node-type "func_literal")
          (app treesit-node-children
               `(,_
                 ,(pred testrun--go-func-testing-parameter-list-p)
                 ,_)))
     t)
    (_ nil)))


(defun testrun--go-parse-t-run-node (node)
  "Recognizes if the treesitter NODE is like t.Run(.., func(t *testing.T) {})."
  (pcase node
    ((and (pred treesit-node-p)
          (app treesit-node-type "call_expression")
          (app treesit-node-children
               `(,(and (app treesit-node-type "selector_expression")
                       (app treesit-node-children
                            `(,_
                              ,_
                              ,(app treesit-node-text "Run"))))
                 ,(and (app treesit-node-type "argument_list")
                       (app treesit-node-children
                            `(,_
                              ,x
                              ,_
                              ,(pred testrun--go-func-testing-node-p)
                              ,_))))))
     (json-parse-string (treesit-node-text x t)))
    (_ nil)))


(defun testrun--go-test-command-at-point ()
  "Return the test command at point for Go."
  ;; Unless there is a `treesit-parser' already, create one.
  (unless (treesit-parser-list)
    (treesit-parser-create 'go))
  (let ((c (testrun--go-recognize-test-chain)))
    (if c
        (format "go test -test.run %s"
                (shell-quote-argument
                 (string-join (mapcar (lambda (x) (format "^%s$" x)) c) "/")))
        nil
      (error "Not inside a Go test"))))


;;;; Implementation


(defun testrun--pick-backend ()
  "Pick a backend for the current major mode."
  (let ((selected-backend nil))
    (dolist (backend testrun-backends)
      (when (derived-mode-p (plist-get backend :mode))
        (setq selected-backend (plist-get backend :backend))))
    (if selected-backend
        selected-backend
      (error "No backend found for %s" major-mode))))


(defun testrun--backend-test-command-at-point (backend)
  "Determine a test command from point for the given BACKEND."
  (funcall (plist-get (funcall backend) :test-command-at-point)))


(provide 'testrun)
;;; testrun.el ends here
