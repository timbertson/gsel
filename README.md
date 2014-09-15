# `gsel`

`gsel` is a fuzzy selector, inspired by [selecta](https://github.com/garybernhardt/selecta).

You pipe some input into it, and it lets you select a single line very quickly.

So you can do:

    vim $(find . | gsel)

...gsel will pop up, and in a few keystrokes you can select the file you're after, and it'll be
summarily opened in vim.

It's like the "matching" part of many text editors' "jump to file" feature,
but it takes options from the lines of `stdin`, rather than being tied to a particular tool.

This means that (with a little setup), you could use it to fuzzy-select all the things, including:

 - files (from `git ls-files`, `ack -l`, or just `find`)
 - text editor buffers (if you can get your editor to pipe in the names of open buffers)
 - code symbols (using `ctags`)

# Why?

I liked the idea of selecta, but had some issues with it in practice:

 - It doesn't work outside a terminal. I use `gvim` as my main editor,
   so that made selecta a bit of a dead-end.

 - It can be slow: nothing happens until all of stdin is
   fully read. In many cases that's fine, but on a breadth-first-search of a
   large file tree you could often get the file you want well before this point.

`gsel` opens a little GUI window to do its thing, so it doesn't interfere with your
terminal, and can be called from anywhere on your desktop (including graphical editors).

### Isn't running a program and piping it into another program which opens a new graphical window just for this one task really slow?

Not appreciably. The whole process takes less than a tenth of a second.
`gsel` nearly always works faster than you can type, which is all that really matters.

# Installation

### Dependencies:

First get `opam`. Then do:

    $ opam install lwt lablgtk

### Building:

    $ ./tools/gup

The result is in `bin/gsel`

# Known issues:

The gui is not very polished.

There's no integration with editors.

It operates on bytes, not unicode characters.

You need to compile it yourself.

Assuming I keep using `gsel` in anger, I'll probably fix most of these eventually.

