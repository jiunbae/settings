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
        retval=$($1 2>&1 >/dev/null) && retval=true;
    } &> /dev/null;
    echo "$retval";
}

download() {
    if [[ -f $2 && $OVERWRITE = false ]]; then
        :
    else
        curl -sLf $1 --output $2;
    fi
}

update_profile() {
    FLAG=false;
    PATTERN="## $1"
    while read line; do
        if [[ $line =~ $PATTERN ]] ; then 
            FLAG=true; break;  
        fi
    done < $PROFILE
    if [ $FLAG = false ]; then
        echo "$PATTERN$2" >> $PROFILE
        PROFILE_DRAFT=true;
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

zsh() {
    # install zsh and requirements
    $SUDOPREFIX $MANAGER install git zsh -y

    # install omz
    $SHELL -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

    # plugins
    $GIT clone https://github.com/zdharma/fast-syntax-highlighting.git ~/.oh-my-zsh/custom/plugins/fast-syntax-highlighting
    $GIT clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions

    $( download $URLPREFIX/.zshrc ~/.zshrc )

    $PROFILE=~/.zshrc
    $SUDOPREFIX chsh -s `which zsh`
}

change_locale() {
    $SUDOPREFIX $MANAGER install locales -y
    $SUDOPREFIX locale-gen en_US.UTF-8

    $( update_profile "Locale" "
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
    " )
}

vim() {
    $SUDOPREFIX $MANAGER install neovim -y
    
    mkdir -p ~/.SpaceVim.d
    curl -sLf https://spacevim.org/install.sh | bash
    $( download $URLPREFIX/.SpaceVim.d/init.toml ~/.SpaceVim.d/init.toml )

    $( update_profile "Vim" "
alias vim=nvim
export EDITOR=vim
    " )
}

tmux() {
    $SUDOPREFIX $MANAGER install tmux -y
    $GIT clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

    $( download $URLPREFIX/.tmux.conf ~/.tmux.conf )
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
    ~/.fzf/install
}

########################################
# Get options
arguments=$(
    whiptail --title "Selet options" --separate-output --checklist "Select options"\
        10 60 5\
        1. "Change source mirror [kakao]" on\
        2. "Install default packages" on\
        3. "Install zsh and change default shell" on\
        4. "Change default locale [en_US]" on\
        5. "Install NeoVim/SpaceVim and set default editor" on\
        6. "Install tmux and change default config" on\
        7. "Install conda python and init conda" on\
        8. "Change pip mirror [kakao]" on\
        9. "Install 'exa' to replace 'ls'" on\
        0. "Install 'fzf': fuzzy finder" on\
        3>&1 1>&2 2>&3
)

$SUDOPREFIX $MANAGER update &> /dev/null;

for arg in $arguments; do
    case $arg in
    1.) 
        title="Change source mirror [kakao]"
        result=$( install change_mirror )
        if [ "$result" = true ]; then
            echo -e "\xE2\x9C\x94 $title"
        else
            echo -e "\xE2\x9D\x8C $title Failed"
            if [ "$VERBOSE" = true ]; then
                echo -e "$result"
            fi
        fi
        ;;
    2.) 
        title="Install default packages"
        result=$( install default_packages )
        if [ "$result" = true ]; then
            echo -e "\xE2\x9C\x94 $title"
        else
            echo -e "\xE2\x9D\x8C $title Failed"
            if [ "$VERBOSE" = true ]; then
                echo -e "$result"
            fi
        fi
        ;;
    3.) 
        title="Install zsh and change default shell"
        result=$( install zsh )
        if [ "$result" = true ]; then
            echo -e "\xE2\x9C\x94 $title"
        else
            echo -e "\xE2\x9D\x8C $title Failed"
            if [ "$VERBOSE" = true ]; then
                echo -e "$result"
            fi
        fi
        ;;
    4.) 
        title="Change default locale [en_US]"
        result=$( install change_locale )
        if [ "$result" = true ]; then
            echo -e "\xE2\x9C\x94 $title"
        else
            echo -e "\xE2\x9D\x8C $title Failed"
            if [ "$VERBOSE" = true ]; then
                echo -e "$result"
            fi
        fi
        ;;
    5.) 
        title="Install Neo/SpaceVim and set default editor"
        result=$( install vim )
        if [ "$result" = true ]; then
            echo -e "\xE2\x9C\x94 $title"
        else
            echo -e "\xE2\x9D\x8C $title Failed"
            if [ "$VERBOSE" = true ]; then
                echo -e "$result"
            fi
        fi
        ;;
    6.) 
        title="Install tmux and change default config"
        result=$( install tmux )
        if [ "$result" = true ]; then
            echo -e "\xE2\x9C\x94 $title"
        else
            echo -e "\xE2\x9D\x8C $title Failed"
            if [ "$VERBOSE" = true ]; then
                echo -e "$result"
            fi
        fi
        ;;
    7.) 
        title="Install conda python and init conda"
        result=$( install conda )
        if [ "$result" = true ]; then
            echo -e "\xE2\x9C\x94 $title"
        else
            echo -e "\xE2\x9D\x8C $title Failed"
            if [ "$VERBOSE" = true ]; then
                echo -e "$result"
            fi
        fi
        ;;
    8.) 
        title="Change pip mirror [kakao]"
        result=$( install change_pip )
        if [ "$result" = true ]; then
            echo -e "\xE2\x9C\x94 $title"
        else
            echo -e "\xE2\x9D\x8C $title Failed"
            if [ "$VERBOSE" = true ]; then
                echo -e "$result"
            fi
        fi
        ;;
    9.) 
        title="Install 'exa' to replace 'ls'"
        result=$( install exa )
        if [ "$result" = true ]; then
            echo -e "\xE2\x9C\x94 $title"
        else
            echo -e "\xE2\x9D\x8C $title Failed"
            if [ "$VERBOSE" = true ]; then
                echo -e "$result"
            fi
        fi
        ;;
    0.) 
        title="Install 'fzf': fuzzy finder"
        result=$( install fzf )
        if [ "$result" = true ]; then
            echo -e "\xE2\x9C\x94 $title"
        else
            echo -e "\xE2\x9D\x8C $title Failed"
            if [ "$VERBOSE" = true ]; then
                echo -e "$result"
            fi
        fi
        ;;
    *)
        echo "Invalid arguments"
        break
        ;;
    esac
done

echo "Installation done"

if [ -d "$TEMPDIR" ]; then
    read -p 'Clear temp directory? [Y/n]' -e -i 'y' CLEAR

    if [ $CLEAR == 'y' ]; then
        rm -r $TEMPDIR
    fi
fi
