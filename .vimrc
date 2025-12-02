set t_ti= t_te=
set hls
set ic
"set expandtab
"set shiftwidth=4
"set tabstop=4
set encoding=utf8
set autoindent
set smartindent
set nocompatible
set complete=.,k
set ls=2
set hlsearch incsearch
set autochdir
set bg=light
set ts=8 sts=4 sw=4 noet
set cc=81,101

function! Tab_Or_Complete() " Autocomplete works with TAB when inserting a word
  if col('.')>1 && strpart( getline('.'), col('.')-2, 3 ) =~ '^\w'
    return "\<C-N>"
  else
    return "\<Tab>"
  endif
endfunction

:inoremap <Tab> <C-R>=Tab_Or_Complete()<CR>

autocmd FileType python,sh,bash,zsh,ruby,perl,muttrc let StartComment="#" | let EndComment=""
autocmd FileType php,cpp,javascript let StartComment="//" | let EndComment=""
au BufRead,BufNewFile *.sh,*.pl,*.tcl,*.p6,*.pl6,*.pm let StartComment="#" | let EndComment=""
au BufRead vimrc,.vimrc let StartComment="\"" | let EndComment=""


function! CommentLines()
    try
        execute ":s@^".g:StartComment." @\@g"
        execute ":s@ ".g:EndComment."$@@g"
    catch
        execute ":s@^@".g:StartComment." @g"
        execute ":s@$@ ".g:EndComment."@g"
    endtry
endfunction

" Mark visual block & press c + o to comment/uncomment lines
vmap co :call CommentLines()<CR>


"Damian

highlight Comment term=bold cterm=italic ctermfg=white gui=italic guifg=white
highlight clear Search
highlight       Search    ctermfg=White  ctermbg=Blue  cterm=bold
highlight    IncSearch    ctermfg=White  ctermbg=Red    cterm=bold

"Star-space or dash-space is a bullet
set comments=fb:*,fb:-

set lcs=tab:══»,trail:␣,nbsp:˷
"   Tabs	shown	thusly	and	so
"   Trailing whitespace
"   Non-breaking space

highlight InvisibleSpaces ctermfg=Black ctermbg=Black
call matchadd('InvisibleSpaces', '\S\@<=\s\+\%#\ze\s*$')
