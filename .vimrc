syntax on

set nu
set tabstop=4
set autoindent
set cindent
set title
set wmnu
set showmatch
set nocompatible
set nowrap
set paste

set laststatus=2

set cursorline
hi Cursor ctermbg=15 ctermfg=8
hi CursorLine ctermbg=14 ctermfg=16 cterm=bold guibg=Grey40

set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()
	Plugin 'gmarik/Vundle.vim'
	Plugin 'Syntastic'
	Plugin 'Shougo/neocomplete'
	Plugin 'Shougo/neosnippet'
	Plugin 'Shougo/neosnippet-snippets'
	Plugin 'vim-addon-manager'
	Bundle 'davidhalter/jedi-vim'
	Bundle 'Lokaltog/powerline', {'rtp': 'powerline/bindings/vim/'}
call vundle#end()
	    
set guifont=DejaVu\ Sans\ Mono\ for\ Powerline\ 9
set laststatus=2
