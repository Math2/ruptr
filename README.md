# ruptr

Alternative parallel test runner for Ruby with (partial) compatibility with RSpec, Test::Unit and
Minitest test suites.

The aim is to allow running unmodified test suites, but this doesn't always work.

## Quick start

```
$ gem install ruptr
$ cd project-root-directory
$ ruptr
```

See `ruptr --help` for options. Options `--no-capture-output` and `--monkey-patch` may help some
test suites to run correctly. Use options `-I` to add include paths and `-r` to require extra
libraries if needed.
