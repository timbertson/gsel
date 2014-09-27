if !exists("g:gsel_file_list_command")
	" common alternatives:
	" `ack -l .`
	" `find -type f`
	" `git ls-files`
	let g:gsel_file_list_command="find . -type f"
endif

if !exists("g:gsel_command")
	let g:gsel_command="gsel"
endif

fun! s:system(...)
	" like system(), but returns "" on failure, and chomps trailing newlines
	let l:rv = call("system", a:000)
	if v:shell_error != 0
		return ""
	" else
	" 	echoerr "command failed!"
	end
	" strip trailing newline
	return substitute(l:rv, '\n\+$', '', 'g')
endfun

fun! gsel#Exec(str, command)
	let l:str = fnameescape(a:str)
	if l:str != ""
		" echo("running ".a:command." ".l:str)
		exec(a:command . " " . l:str)
	endif
	call foreground()
endfun

fun! gsel#DiscardPendingInputHook()
	" call feedkeys("xx", "n")
	call inputrestore()
	sleep 100m
	call feedkeys("xx\<esc>\<esc>", "n")
	return ""
endfun

fun! gsel#DiscardPendingInput()
	" When starting `gsel`, we might get some of its
	" input before it had a chance to grab focus.
	" So we drop this input by stashing it and then popping it
	" in the middle of a harmless `echo` command (which we then abandon)
	call inputsave()
	" sandbox call inputrestore()
	" normal "\ <c-r>=inputrestore()
	"<cr>
	" normal :call input("ignore")<cr><c-r>=("HELLO")<cr>
	" call feedkeys(":echo \<c-r>=gsel#DiscardPendingInputHook()\<cr>")
	" call feedkeys(":\<c-r>=(inputrestore() ? feedkeys('xx') : feedkeys('\" '))\<cr>\<esc>")
	" call feedkeys(":echo 123")
	" normal :call input("ignore")<cr><c-r>=("".inputrestore())<cr>
	" call feedkeys(":call input(\"ignore:\")\<cr>\<c-r>=(\"\\<esc>\".inputrestore())\<cr>\<esc>\<esc>")
	" call inputrestore()
	" call feedkeys("\<esc>", "n")
endfun

" fun! gsel#TestInput()
" 	call s:system("sleep 0.3")
" 	call gsel#DiscardPendingInput()
" endfun
" nnoremap <c-y> :call gsel#TestInput()<cr>

" pass 0 as extra arg to suppress concatenation of `base` to the result
fun! gsel#Find(base, ...)
	" find a file under `base` with gsel and return it
	let l:rv = s:system("cd ".shellescape(a:base)." && ".g:gsel_file_list_command." 2>/dev/null | env GSEL_DEBUG=1 ".g:gsel_command)
	call gsel#DiscardPendingInput()

	if l:rv == ""
		return ""
	endif
	if a:0 > 0
		if a:1 == 0
			return l:rv
		endif
	endif
	return a:base."/".l:rv
endfun

fun! gsel#CompleteCommand()
	" should only be called from command-mode
	let l:cmd = getcmdline()
	let l:pos = getcmdpos()
	let l:prefix_raw = "./"
	let l:prefix = "./"
	if l:pos > 1
		let l:char = l:cmd[l:pos-2]
		if l:char != " "
			let l:tokens = split(l:cmd)
			" XXX we just assume we're completing the last token
			" TODO if we are not in a dir, we could use dirname()
			" and then return "\b" * n to get rid of the broken path component
			let l:num_tokens = len(l:tokens)
			let l:prefix_raw = l:tokens[l:num_tokens-1]
			let l:prefix = fnamemodify(l:prefix_raw, ":p") " expand ~, etc
		endif
	endif

	" echoerr "SELECTING IN ".l:prefix
	let l:selected = gsel#Find(l:prefix, 0)
	if l:selected == ""
		return ""
	endif
	" echoerr "SELECTED ".l:selected
	let l:trailing_char = l:prefix_raw[(strlen(l:prefix_raw)) - 1]
	" echoerr "LEN ".strlen(l:prefix_raw)." TRAIL ".l:trailing_char
	let l:selected = fnameescape(l:selected)
	if l:trailing_char != "/"
		let l:selected = "/".(l:selected)
	endif
	return l:selected
endfun

fun! gsel#FindDo(base, command)
	" perform a vim command with the output of `gsel`
	call gsel#Exec(fnameescape(gsel#Find(a:base)), a:command)
endfun

" buffer list code copied from:
" https://github.com/kien/ctrlp.vim/blob/master/autoload/ctrlp/buffertag.vim
fun! gsel#BufferList()
	let ids = filter(range(1, bufnr('$')), 'empty(getbufvar(v:val, "&buftype")) && getbufvar(v:val, "&buflisted")')
	let names = []
	for id in ids
		let bname = bufname(id)
		let ebname = bname == ''
		let fname = fnamemodify(ebname ? '['.id.'*No Name]' : bname, ':.')
		cal add(names, fname)
	endfor
	return [ids, names]
endfun

fun! BufHasActiveWindow(bufid)
	for i in range(tabpagenr('$'))
		let l:bufs = tabpagebuflist(i + 1)
		if index(l:bufs, a:bufid) >= 0
			return 1
		endif
	endfor
	return 0
endfun

fun! gsel#BufferSwitch()
	let l:bufinfo = gsel#BufferList()
	let l:bufids= l:bufinfo[0]
	let l:bufnames = join(l:bufinfo[1], "\n")
	let l:selected = s:system(g:gsel_command ." --index", bufnames)
	call gsel#DiscardPendingInput()
	if l:selected != ""
		let l:idx = str2nr(l:selected)
		let l:bufid = l:bufids[l:idx]
		if BufHasActiveWindow(l:bufid)
			" blech... temporarily modify switchbuf
			" so that we switch instead of splitting
			let [swb, &swb] = [&swb, 'usetab']
			exec('sbuffer '. l:bufid)
			let &swb = swb
		else
			" open the buffer in the current window
			exec('buffer '.l:bufid)
		endif
	endif
	call foreground()
endfun

fun! gsel#DefaultMappings()
	" find & insert a file on the command line
	" TODO: use current token to restrict search?
	cnoremap <C-f> <C-r>=gsel#CompleteCommand()<cr>

	" jump to a file from the current cwd
	nnoremap <silent> <C-f> :call gsel#FindDo(".", ":drop")<cr>

	" jump to a file from the current file's dirname
	nnoremap <silent> <leader>F :call gsel#FindDo(expand("%:p:h"), ":drop")<cr>

	" jump to buffer
	nnoremap <silent> <C-b> :call gsel#BufferSwitch()<cr>
endfun

