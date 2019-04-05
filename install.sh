# change apt mirror to kakao
sudo cp /etc/apt/sources.list /etc/apt/sources.list.org
sed -e 's/\(us.\)\?archive.ubuntu.com/mirror.kakao.com/g' -e 's/security.ubuntu.com/mirror.kakao.com/g' < /etc/apt/sources.list.org > sources.list
sudo mv sources.list /etc/apt
sudo apt update

# install conda (Miniconda)
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh
bash ~/miniconda.sh -b -p $HOME/conda
export CONDA_HOME=$HOME/conda
export PYTHON_VERSION='python3.6'
rm ~/miniconda.sh

# change pip mirror to kakao
mkdir -p ~/.pip
cp pip.conf ~/.pip

# install locale for en_US
sudo apt install locales -y
locale-gen en_US.UTF-8

# install default packages
sudo apt install wget vim zsh -y

# install powerline
pip install powerline-status

# install vundle
git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim
cp .vimrc ~/
vim +PluginInstall +qall

# install oh-my-zsh
sh -c "$(wget https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh -O -)"

# install omz plugins
git clone https://github.com/zdharma/fast-syntax-highlighting.git ~/.oh-my-zsh/custom/plugins/fast-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions

cp .zshrc ~/

# install tpm
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

cp .tmux.conf ~/
tmux source "$CONDA_HOME/lib/$PYTHON_VERSION/site-packages/powerline/bindings/tmux/powerline.conf" 
tmux source "$HOME/.tmux.conf"

