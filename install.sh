# change apt mirror to kakao
cp /etc/apt/sources.list /etc/apt/sources.list.org
sed -e 's/\(us.\)\?archive.ubuntu.com/mirror.kakao.com/g' -e 's/security.ubuntu.com/mirror.kakao.com/g' < /etc/apt/sources.list.org > /etc/apt/sources.list
apt update

# install locale for en_US
apt install locales -y
locale-gen en_US.UTF-8

# install default packages
apt install wget vim zsh -y

# init submodules
git submodule init
git submodule update

# install vundle
git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim
cp .vimrc ~/
vim +PluginInstall +qall

# install oh-my-zsh
sh -c "$(wget https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh -O -)"
cp .zshrc ~/
cp -r .zsh ~/

# install config omz
cp zsh-autosuggestions.zsh ~/.zsh/zsh-autosuggestions
