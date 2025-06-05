# testrun.el

Runs [Go](https://go.dev) tests at point.

## Config

```emacs-lisp
(use-package testrun
  :bind (("C-c t SPC" . testrun-at-point)
         ("C-c t t"   . testrun-repeat)
         ("C-c t d".  . testrun-in-current-directory)
         ("C-c t f".  . testrun-in-current-file)
         ("C-c t v".  . testrun-toggle-verbosity))
```

## Usage

### testrun-at-point

If point is within `TestFeature`, this command runs `go test -test.run TestFeature`.

```go
func TestFeature(t *testing.T) {
    t.Parallel()
    ...
}
```

It also recognizes sub-tests and runs `go test -test.run TestFeature/case1` if in a sub-test:

```go
func TestFeature(t *testing.T) {
    t.Parallel()

    t.Run("case1", func(t *testing.T) {
        t.Parallel()
        ...
    })
}
```

### testrun-in-current-directory

Runs `go test .`

### testrun-in-current-file

Collects all Go tests in current file and runs `go test -test.run "^(Test1|Test2|Test3)$`

### testrun-repeat

Repeats the most recently executed test command. This is really useful to call when editing the code under test to
repeatedly test it.

### testrun-toggle-verbosity

Toggles appending `-test.v` to `go test` commands.

### prefix argument

All commands support the prefix argument, for example you can run `C-u M-x testrun-at-point`. This will add `-update`
to the Go testing command, for example `go test -update TestFeature`. Tests using
[autogold](https://github.com/hexops/autogold) recognize this flag to update golden files.
