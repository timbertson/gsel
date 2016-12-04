<img src="http://gfxmonk.net/dist/status/project/gsel.png">

# `gsel`

`gsel` is a fuzzy selector, inspired by [selecta](https://github.com/garybernhardt/selecta).

You pipe some input into it, and it lets you select a single line very quickly.

So you can do:

    vim $(find . | gsel)

...gsel will pop up, and in a few keystrokes you can select the file you're after, and it'll be
summarily opened in vim.

It looks a bit like this:

![gsel screenshot](/screenshots/sample1.png?raw=true)

It's like the "matching" part of many text editors' "jump to file" feature,
but it takes options from the lines of `stdin`, rather than being tied to a particular tool.

This means that (with a little setup), you could use it to fuzzy-select All The Things, including:

 - files (from `git ls-files`, `ack -l`, or just `find`)
 - text editor buffers
 - code symbols (using `ctags`)
 - anything else you have a list of

# Why?

I liked the idea of `selecta`, but had some issues with it in practice:

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

If you use [nix](http://nixos.org/nixpkgs/), you can just `nix-shell`.

Otherwise... have a look in nix/default.nix, you'll need at least vala, gtk3, opam and some opam packages (listed in that file).

### Building:

    $ ./tools/gup compile

### Running:

./bin/gsel

The GUI is implemented as a tiny shared library, which ocaml calls via FFI. Maybe this is crazy, but it was the easiest migration from lablgtk2 to gtk3 (which has no ocaml bindings). See src/gselui.vala for the implementation.

This means you'll need `_build/lib` on $LD_LIBRARY_PATH when running gsel. Or, you can set $PREFIX when compiling, and $PREFIX/lib will be added to gsel's runtime search path.

# Vim integration:

The `vim/` directory provides autoload functions which provide building blocks for calling
gsel and doing useful things with the results. The idea is that you can plug these functions
together as you like, but if you prefer to use my default key bindings you can just
`call gsel#DefaultMappings()`.

### Configuration:

The default way to get a recursive file list is `find . -type f`. That's pretty
slow, and includes a bunch of stuff (e.g `.git` folder contents) that you probably
don't want. So you may want to use a better alternative of your choice, like one of:

  let g:gsel_file_list_command = "git ls-files ."
  let g:gsel_file_list_command = "ack -l ."
  let g:gsel_file_list_command = "ag -l ."

If gesl isn't on your $PATH or something silly like that, you can specify:

    let g:gsel_command = "/path/to/gsel"

If you want to create your own bindings, go nuts! The default ones look like this:

    " Command mode:
    " <c-f>: complete the current arg via find
    " <c-b>: insert the filename of an open buffer
    cnoremap <C-f> <C-r>=gsel#CompleteCommand()<cr>
    cnoremap <C-b> <C-r>=gsel#BufferFilename()<cr>
    
    " Normal mode --
    " <c-f>: jump to a file from the current cwd
    " <leader>f: jump to a file from the directory of the active file
    " <c-b>: jump to buffer
    nnoremap <silent> <C-f> :call gsel#FindDo(".", ":drop")<cr>
    nnoremap <silent> <leader>F :call gsel#FindDo(expand("%:p:h"), ":drop")<cr>
    nnoremap <silent> <C-b> :call gsel#BufferSwitch()<cr>

# Other integration:

Write some, send a pull-request, and get your name here :D

# Known issues:

There's no integration with editors.

It operates on bytes, not unicode characters.

You need to compile it yourself.

Assuming I keep using `gsel` in anger, I'll probably fix most of these eventually.

