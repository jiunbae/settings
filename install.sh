# install git, wget
sudo apt install git wget -y

# install htop, bat
sudo apt install htop bat -y

# init submodules
git submodule init
git submodule update

# install vundle
git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim
cp .vimrc ~/
vim +PluginInstall +qall

# install zsh
sudo apt install zsh -y

# install oh-my-zsh
sh -c "$(wget https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh -O -)"
cp .zshrc ~/
cp -r .zsh ~/

# install config omz
cp zsh-autosuggestions.zsh ~/.zsh/zsh-autosuggestions

