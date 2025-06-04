;;; testrun.el --- helpers for running tests  -*- lexical-binding:t -*-
;;;
;;; Version: 1
;;;
;;; Commentary:

;;; Cater to the most common scenarios:
;;; - run a test at point
;;; - TODO jump to recently used tests
;;; - TODO run tests in current project

;;; Code:

(require 'compile)
(require 'treesit)


;;;; Customization


(defcustom testrun-backends
  '((:mode go-ts-mode :backend testrun--go-backend)
    (:mode go-mode :backend testrun--go-backend))
  "A list of backends to use for running tests."
  :type '(sexp)
  :group 'languages)


(defcustom testrun-switch-to-compilation-buffer nil
  "A flag that enables switching to the compilation buffer after each test command."
  :type 'boolean
  :group 'languages)


;;;; Methods


;;;###autoload
(defun testrun-at-point (arg)
  "Run a test at point."
  (interactive "p")
  (let* ((b (testrun--pick-backend))
         (c (testrun--apply b :test-command-at-point arg)))
    (testrun--compile c)))

;;;###autoload
(defun testrun-in-current-file (arg)
  "Run all tests in the current file."
  (interactive "p")
  (let* ((b (testrun--pick-backend))
         (c (testrun--apply b :test-command-current-file arg)))
    (testrun--compile c)))

;;;###autoload
(defun testrun-in-current-directory (arg)
  "Run tests in the current directory."
  (interactive "p")
  (let* ((b (testrun--pick-backend))
         (c (testrun--apply b :test-command-current-directory arg)))
    (testrun--compile c)))


;;;###autoload
(defun testrun-repeat ()
  "Repeat the most recently executed test command."
  (interactive)
  (testrun--recompile))


;;;###autoload
(defun testrun-toggle-verbosity ()
  "Toggle verbosity level for testing."
  (interactive)
  (let* ((b (testrun--pick-backend)))
    (testrun--apply b :toggle-verbosity)))


;;;; Golang


(defun testrun--go-backend ()
  "Supports testrun for Golang."
  (list :test-command-at-point #'testrun--go-test-command-at-point
        :test-command-current-directory #'testrun--go-test-command-current-directory
        :test-command-current-file #'testrun--go-test-command-current-file
        :toggle-verbosity #'testrun--go-toggle-verbosity))


(defvar testrun--go-verbose nil)


(defun testrun--go-toggle-verbosity ()
  "Switch between verbose and normal testing."
  (interactive)
  (setq testrun--go-verbose (not testrun--go-verbose))
  (message (if testrun--go-verbose "-test.v enabled" "-test.v disabled")))


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


(defun testrun--go-test-command-at-point (arg)
  "Return the test command at point for Go."
  ;; Unless there is a `treesit-parser' already, create one.
  (unless (treesit-parser-list)
    (treesit-parser-create 'go))
  (let ((c (testrun--go-recognize-test-chain)))
    (if c
        (format "go test%s%s -test.run %s"
                (if testrun--go-verbose " -test.v" "")
                (if (equal arg 4) " -update" "")
                (shell-quote-argument
                 (string-join (mapcar (lambda (x) (format "^%s$" x)) c) "/")))
        nil
      (error "Not inside a Go test"))))


(defun testrun--go-test-command-current-directory (arg)
  "Return the test command for testing current directory in Go."
  (concat "go test"
          (if testrun--go-verbose " -test.v" "")
          (if (equal arg 4) " -update" "")
          " ."))

(defvar testrun--go-tests-fns-in-node
  (treesit-query-compile
   'go
   '(((function_declaration
       name: (identifier) @function-name (:match "^Test" @function-name)
       parameters: (parameter_list
                    (parameter_declaration
                     name: (identifier)
                     type: (pointer_type
                            (qualified_type
                             package: (package_identifier) @pkg (:equal "testing" @pkg)
                             name: (type_identifier) @type-name  (:equal "T" @type-name)))))
       @parameter-list (:pred testrun--3-children-predicate @parameter-list)))))
  "A `treesit' query that will match all function nodes that will be run as tests.")

(defun testrun--3-children-predicate (node)
  "A predicate for tree-sitter: (= (children NODE) 3).

`treesit' doesn't allow this function to be inlined or moved out of the global scope."
  (= 3 (treesit-node-child-count node)))

(defun testrun--go-test-command-current-file (arg)
  "Return a command that runs all tests in the current directory in Go."
  ;; Ensure there is a `treesit-parser` for Go; create one if needed.
  (unless (treesit-parser-list)
    (treesit-parser-create 'go))
  (if-let ((matches (treesit-query-capture (car (treesit-parser-list nil 'go)) testrun--go-tests-fns-in-node)))
      (concat "go test "
              (when testrun--go-verbose "-test.v ")
              (when (equal arg 4) "-update ")
              (format "-test.run \"^(%s)$\" "
                      (mapconcat
                       (lambda (match) (treesit-node-text (cdr match)))
                       (seq-filter (lambda (match) (eq (car match) 'function-name)) matches)
                       "|"))
              "./...")
    (user-error "No test functions found")))

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


(defun testrun--apply (backend method-selector &rest args)
  "Dispatches a METHOD-SELECTOR call with ARGS to the given BACKEND."
  (apply (plist-get (funcall backend) method-selector) args))


(defun testrun--compile (c)
  (compile c)
  (when testrun-switch-to-compilation-buffer
    (compilation-goto-in-progress-buffer)))


(defun testrun--recompile ()
  (recompile)
  (when testrun-switch-to-compilation-buffer
    (compilation-goto-in-progress-buffer)))


(provide 'testrun)
;;; testrun.el ends here
