# testrun.el

Runs tests at point. Features:

- supports Go tests
- recognizes Go sub-tests at point
- can toggle `-test.v` flag
- can toggle `-update` flag for [autogold](https://github.com/hexops/autogold) tests

## Usage

```emacs-lisp
(use-package testrun
  :bind (("C-c t SPC" . testrun-at-point)
         ("C-c t t"   . testrun-repeat)
         ("C-c t d".  . testrun-in-current-directory)
         ("C-c t v".  . testrun-toggle-verbosity))
```
