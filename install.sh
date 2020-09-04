#!/bin/bash
SUDOPREFIX=$([ $EUID -eq 0 ] && echo "" || echo "sudo")
MANAGER=apt
SHELL=sh
GIT=git
TEMPDIR=temp
URLPREFIX="https://raw.githubusercontent.com/MaybeS/settings/master"
VERBOSE=false
OVERWRITE=false
PROFILE=~/.bashrc
PROFILE_DRAFT=false
DRAFT=false
DPKG=dpkg

########################################
# Arguments
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case $1 in
    -m|--manager)
        MANAGER="$2"
        shift
        shift
        ;;
    -s|--shell)
        SHELL="$2"
        shift
        shift
        ;;
    -g|--git)
        GIT="$2"
        shift
        shift
        ;;
    -t|--temp)
        TEMPDIR="$2"
        shift
        shift
        ;;
    -u|--url)
        URLPREFIX="$2"
        shift
        shift
        ;;
    -p|--profile)
        PROFILE="$2"
        shift
        shift
        ;;
    --overwrite)
        OVERWRITE=true
        shift
        ;;
    --verbose)
        DEFAULT=true
        shift # past argument
        ;;
    *)    # unknown option
        POSITIONAL+=("$1") # save it in an array for later
        shift # past argument
        ;;
    esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

########################################
# Install, download and update
install() {
    {
        retval=$($1 2>&1 >/dev/null) && retval=true
    } &> /dev/null
    echo "$retval"
}

install_wrapper() {
    result=$( install $1 )
    if [[ ( "$result" = true ) || ( -z "$result" ) ]]; then
        echo "echo -e \xE2\x9C\x94 $2"
    else
        echo "echo -e \xE2\x9D\x8C $2 Failed"
        if [ "$VERBOSE" = true ]; then
            echo "echo -e $result"
        fi
    fi
}

download() {
    if [[ -f $2 && ($3 && $OVERWRITE = false) ]]; then
        :
    else
        curl -sLf $1 --output $2
    fi
}

update_profile() {
    FLAG=false
    PATTERN="## $1"
    while read line; do
        if [[ $line =~ $PATTERN ]] ; then 
            FLAG=true
            break
        fi
    done < $PROFILE
    if [ $FLAG = false ]; then
        echo "$PATTERN$2" >> $PROFILE
        PROFILE_DRAFT=true
    fi
}

########################################
# Install functions
change_mirror() {
    $SUDOPREFIX cp /etc/apt/sources.list /etc/apt/sources.list.org;
    sed -e 's/\(us.\)\?archive.ubuntu.com/mirror.kakao.com/g' -e 's/security.ubuntu.com/mirror.kakao.com/g' < /etc/apt/sources.list.org > sources.list;
    $SUDOPREFIX mv sources.list /etc/apt;
    $SUDOPREFIX $MANAGER update;
}

default_packages() {
    $SUDOPREFIX $MANAGER install curl vim zip build-essential -y;
}

change_locale() {
    $SUDOPREFIX $MANAGER install locales -y
    $SUDOPREFIX locale-gen en_US.UTF-8

    $( update_profile "Locale" "
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
    " )
}

zsh() {
    # install omz
    $SHELL -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended > /dev/null 2>&1;

    # plugins
    $GIT clone https://github.com/zdharma/fast-syntax-highlighting.git ~/.oh-my-zsh/custom/plugins/fast-syntax-highlighting
    $GIT clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions

    curl -sLf $URLPREFIX/.zshrc --output ~/.zshrc

    export PROFILE=~/.zshrc
    $SUDOPREFIX chsh -s `which zsh`
}

vim() {
    mkdir -p ~/.SpaceVim.d
    curl -sLf https://spacevim.org/install.sh | bash
    $( download $URLPREFIX/.SpaceVim.d/init.toml ~/.SpaceVim.d/init.toml )

    $( update_profile "Vim" "
alias vim=nvim
export EDITOR=vim
    " )
}

tmux() {
    $GIT clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
    
    curl -sLf $URLPREFIX/.tmux.conf --output ~/.tmux.conf
}

conda() {
    mkdir -p $TEMPDIR

    $( download https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh $TEMPDIR/miniconda.sh )
    $SHELL $TEMPDIR/miniconda.sh -b -p $HOME/conda

    export CONDA_HOME=$HOME/conda

    $( download $URLPREFIX/.condarc ~/.condarc )
    $( update_profile "Conda" "
export CONDA_HOME=$HOME/conda
export PATH=$CONDA_HOME/bin:$PATH

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('$CONDA_HOME/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "$CONDA_HOME/etc/profile.d/conda.sh" ]; then
        . "$CONDA_HOME/etc/profile.d/conda.sh"
    else
        export PATH="$CONDA_HOME/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<
    ")
}

change_pip() {
    mkdir -p ~/.pip
    $( download $URLPREFIX/pip.conf ~/.pip/pip.conf)
}

exa() {
    mkdir -p $TEMPDIR

    $( download https://github.com/ogham/exa/releases/download/v0.9.0/exa-linux-x86_64-0.9.0.zip $TEMPDIR/exa.zip )
    unzip -u $TEMPDIR/exa.zip -d $TEMPDIR
    $SUDOPREFIX mv $TEMPDIR/exa-linux-x86_64 /usr/local/bin/exa

    $( update_profile "exa" "
alias ls=exa
    ")
}

fzf() {
    $GIT clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    ~/.fzf/install --all
}

gcc() {
    $SUDOPREFIX apt install software-properties-common
    $SUDOPREFIX add-apt-repository ppa:ubuntu-toolchain-r/test

    $SUDOPREFIX apt install gcc-9 g++-9 -y
    $SUDOPREFIX update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 90 --slave /usr/bin/g++ g++ /usr/bin/g++-9 --slave /usr/bin/gcov gcov /usr/bin/gcov-9
}

git() {
    $GIT config --global core.autocrlf true
}

fd() {
    $( download https://github.com/sharkdp/fd/releases/download/v8.1.1/fd_8.1.1_amd64.deb $TEMPDIR/fd.deb)
    yes | $SUDOPREFIX $DPKG -i $TEMPDIR/fd.deb
}

bat() {
    $( download https://github.com/sharkdp/bat/releases/download/v0.15.4/bat_0.15.4_amd64.deb $TEMPDIR/bat.deb)
    yes | $SUDOPREFIX $DPKG -i $TEMPDIR/bat.deb
}

########################################
# Check requirements
if [[ ! $(command -v whiptail) ]]; then
    echo "Install requirements ... [whiptail]"
    $SUDOPREFIX $MANAGER install whiptail -y > /dev/null 2>&1;
fi

########################################
# Get options
arguments=$(
    whiptail --title "Jiun's Settings" --separate-output --checklist "Selet options using arrow key and <TAB>" \
        32 80 11 \
        1. "Change source mirror [kakao]" on\
        2. "Install default packages" on\
        3. "Change default locale [en_US]" on\
        4. "Install zsh and change default shell" on\
        5. "Install NeoVim/SpaceVim and set default editor" on\
        6. "Install tmux and change default config" on\
        7. "Install conda python and init conda" on\
        8. "Change pip mirror [kakao]" on\
        9. "Install 'exa' to replace 'ls'" on\
        10. "Install 'fzf': fuzzy finder" on\
        11. "Install 'fd': alternative to 'find'" on\
        12. "Install 'bat': alternative to 'cat'" on\
        3>&1 1>&2 2>&3
)

echo "Update package manager ..."
$SUDOPREFIX $MANAGER update > /dev/null 2>&1;

for arg in $arguments; do
    case $arg in
    1.) 
        $( install_wrapper change_mirror "Change source mirror [kakao]" )
        ;;
    2.) 
        $( install_wrapper default_packages "Install default packages" )
        ;;
    3.)     
        $( install_wrapper change_locale "Change default locale [en_US]" )
        ;;
    4.) 
        # install zsh and requirements
        $SUDOPREFIX $MANAGER install git zsh -y > /dev/null 2>&1;
        $( install_wrapper zsh "Install zsh and change default shell" )
        curl -sLf $URLPREFIX/.zshrc --output ~/.zshrc

        export PROFILE=~/.zshrc
        $SUDOPREFIX chsh -s `which zsh`
        ;;
    5.) 
        $SUDOPREFIX $MANAGER install neovim -y > /dev/null 2>&1;
        $( install_wrapper vim "Install Neo/SpaceVim and set default editor" )
        ;;
    6.) 
        $SUDOPREFIX $MANAGER install tmux -y > /dev/null 2>&1;
        $( install_wrapper tmux "Install tmux and change default config" )
        ;;
    7.) 
        $( install_wrapper conda "Install conda python and init conda" )
        ;;
    8.) 
        $( install_wrapper change_pip "Change pip mirror [kakao]" )
        ;;
    9.) 
        $( install_wrapper exa "Install 'exa' to replace 'ls'" )
        ;;
    10.) 
        $( install_wrapper fzf "Install 'fzf': fuzzy finder" )
        ;;
    11.)
        $( install_wrapper fd "Install 'fd': alternative to 'find'" )
        ;;
    12.)
        $( install_wrapper bat "Install 'bat': alternative to 'cat'" )
        ;;
    *)
        echo "Invalid arguments"
        break
        ;;
    esac
    DRAFT=true
done

if [ $DRAFT = true ]; then
    echo "Installation done"
    echo "---------"
    echo "Go to github.com/powerline/fonts and download the powerline font and set to terminal"
    echo "Exit and restart the terminal."
    echo "-- vim --"
    echo "The first time you open vim, several installations can start."
    echo "-- zsh --"
    echo "If your default shell has not been changed to zsh,"
    echo "you can change the default shell with sudo chsh -s `which zsh`."
    echo "---------"

    if [[ -d "$TEMPDIR" ]]; then
        rm -r $TEMPDIR;
    fi
else
    echo "Installation canceled"
fi
