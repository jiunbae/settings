# init submodules
git submodule init
git submoudle update

# install vundle
git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim
cp .vimrc ~/
vim +PluginInstall +qall

# install zsh
sudo apt-get install zsh -y

# install oh-my-zsh
sh -c "$(wget https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh -O -)"
cp .zshrc ~/
cp -r .zsh ~/

# install config omz
cp zsh-autosuggestions.zsh ~/.zsh/zsh-autosuggestions
