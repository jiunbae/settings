# change apt mirror to kakao
sudo cp /etc/apt/sources.list /etc/apt/sources.list.org
sed -e 's/\(us.\)\?archive.ubuntu.com/mirror.kakao.com/g' -e 's/security.ubuntu.com/mirror.kakao.com/g' < /etc/apt/sources.list.org > sources.list
sudo mv sources.list /etc/apt
sudo apt update

# install default packages
sudo apt install wget curl tmux zsh -y

# install locale for en_US
sudo apt install locales -y
locale-gen en_US.UTF-8

# install tpm
# --- Shell
# install powerline
pip install powerline-status

# install oh-my-zsh
sh -c "$(wget https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh -O -)"

# install omz plugins
git clone https://github.com/zdharma/fast-syntax-highlighting.git ~/.oh-my-zsh/custom/plugins/fast-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions

cp .zshrc ~/.zshrc

# --- Python
# install conda (Miniconda)
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh
bash ~/miniconda.sh -b -p $HOME/conda
export CONDA_HOME=$HOME/conda
export PYTHON_VERSION='python3.6'
rm ~/miniconda.sh
cp .condarc ~/.condarc

# change pip mirror to kakao
mkdir -p ~/.pip
cp pip.conf ~/.pip

# --- Utilities
# install Tmux
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

cp .tmux.conf ~/
tmux source "$CONDA_HOME/lib/$PYTHON_VERSION/site-packages/powerline/bindings/tmux/powerline.conf" 
tmux source "$HOME/.tmux.conf"

# install neovim
sudo add-apt-repository ppa:neovim-ppa/stable -y
sudo apt update
sudo apt install neovim -y

# install spacevim
curl -sLf https://spacevim.org/install.sh | bash
mkdir ~/.SpaceVim.d
cp .SpaceVim.d/init.toml ~/.SpaceVim.d/init.toml

source ~/.zshrc

