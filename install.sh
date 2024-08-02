#!/bin/bash


########################################
# Update global variables
# See also https://stackoverflow.com/a/47556292/5615965
_passback() { while [ 1 -lt $# ]; do printf '%q=%q;' "$1" "${!1}"; shift; done; return $1; }
passback() { _passback "$@" "$?"; }
_capture() { { out="$("${@:2}" 3<&-; "$2_" >&3)"; ret=$?; printf "%q=%q;" "$1" "$out"; } 3>&1; echo "(exit $ret)"; }
capture() { eval "$(_capture "$@")"; }

########################################
# Globals
SUDOPREFIX=$([ $EUID -eq 0 ] && echo "" || echo "sudo")
SYSTEM=$( uname -s )
MANAGER=apt
SHELL=sh
GIT=git
TEMPDIR=temp
URLPREFIX="https://raw.githubusercontent.com/jiunbae/settings/master"
VERBOSE=false
OVERWRITE=false
PROFILE=~/.zshrc
PROFILE_DRAFT=false
DRAFT=false
DPKG=dpkg
Y_FLAG=-y
LOG_FILE=install.log

prepare_globals_() { 
    passback SUDOPREFIX;
    passback MANAGER;
    passback SHELL;
    passback Y_FLAG;
    passback LOG_FILE;
}
prepare_globals() {
    case $SYSTEM in
        Linux)
            SUDOPREFIX=$([ $EUID -eq 0 ] && echo "" || echo "sudo")
            MANAGER=apt
            SHELL=sh
            Y_FLAG=-y
            ;;
        Darwin)
            SUDOPREFIX=""
            MANAGER=brew
            SHELL=sh
            Y_FLAG=""
            ;;
        *)
            echo "Unsupported system $SYSTEM" >&2
            exit 1
            ;;
    esac
}

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
# Install, download and update, utility functions
install() {
    {
        retval=$($1 2>&1 >/dev/null) && retval=true
    } &> /dev/null
    echo "$retval"
}

install_wrapper() {
    result=$( install $1 )
    echo "$2" >> $LOG_FILE
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
        echo "Downloading $1 to $2" >> $LOG_FILE
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
        echo "Write $1 to $PROFILE" >> $LOG_FILE
        echo "$PATTERN$2" >> $PROFILE
        PROFILE_DRAFT=true
    fi
}

run_task() {
    echo "$2 ..." >&2
    $1 > /dev/null 2>&1;
    echo "$2" >> $LOG_FILE
    if [ $? -ne 0 ]; then
        echo "$2 false" >&2
        echo "false"
        return
    fi
    echo "true"
}

prepare_packages() {
    mkdir -p $TEMPDIR
    echo "Prepare packages" >> $LOG_FILE

    if [[ ! $(command -v whiptail) ]]; then
        if [ "$( run_task "$SUDOPREFIX $MANAGER install whiptail $Y_FLAG" "Install requirements [whiptail]" )" == false ]; then
            return 0
        fi
    fi

    if [ "$( run_task "$SUDOPREFIX $MANAGER update" "Update package manager" )" == false ]; then
        return 0
    fi
    
    if [ "$( run_task "$SUDOPREFIX $MANAGER install git $Y_FLAG" "Install requirements [git]" )" == false ]; then
        return 0
    fi

    if [ "$( run_task "curl https://sh.rustup.rs -sSf | sh -s -- -y" )" == false ]; then
        return 0
    fi
    . "$HOME/.cargo/env"
}

########################################
# Install functions
change_mirror() {
    $SUDOPREFIX cp /etc/apt/sources.list /etc/apt/sources.list.org;
    sed -e 's/\(us.\|kr.\)\?archive.ubuntu.com/mirror.kakao.com/g' -e 's/security.ubuntu.com/mirror.kakao.com/g' < /etc/apt/sources.list.org > sources.list;
    $SUDOPREFIX mv sources.list /etc/apt;
    $SUDOPREFIX $MANAGER update;
}

default_packages() {
    $SUDOPREFIX $MANAGER install curl wget zip gcc g++ $Y_FLAG;
    case $SYSTEM in
        Linux)
            $SUDOPREFIX $MANAGER install build-essential $Y_FLAG;
            ;;
        Darwin)
            xcode-select --install
            ;;
    esac
}

change_locale() {
    $SUDOPREFIX $MANAGER install locales $Y_FLAG
    $SUDOPREFIX locale-gen en_US.UTF-8

    $( update_profile "Locale" "
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
" )
}

zsh() {
    # install omz
    $SHELL -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended > /dev/null 2>&1;
    $SHELL -c "$GIT clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"

    $SHELL -c "$(curl -sLf $URLPREFIX/.zshrc --output ~/.zshrc)"
    $SHELL -c "$(curl -sLf $URLPREFIX/.p10k.zsh --output ~/.p10k.zsh)"

    PROFILE=~/.zshrc
    
    # plugins
    if [[ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting" ]]; then
        $SHELL -c "$GIT clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
    fi

    if [[ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" ]]; then
        $SHELL -c "$GIT clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
    fi

    if [[ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/git-extra-commands" ]]; then
        $SHELL -c "$GIT clone git clone https://github.com/unixorn/git-extra-commands.git ${$ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/git-extra-commands"
    fi

    # change default shell
    $SHELL -c "$SUDOPREFIX chsh -s `which zsh`" >/dev/null 2>&1;
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
    $SHELL -c "$GIT clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm"
    
    $SHELL -c "curl -sLf $URLPREFIX/.tmux.conf --output ~/.tmux.conf"
}

conda() {
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

eza() {
    $( run_task cargo install eza )

    $( update_profile "eza" "
alias ls=eza
")
    
}

fzf() {
    $SUDOPREFIX $MANAGER install fzf
}

gcc() {
    $SUDOPREFIX apt install software-properties-common
    $SUDOPREFIX add-apt-repository ppa:ubuntu-toolchain-r/test

    $SUDOPREFIX apt install gcc-9 g++-9 $Y_FLAG
    $SUDOPREFIX update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 90 --slave /usr/bin/g++ g++ /usr/bin/g++-9 --slave /usr/bin/gcov gcov /usr/bin/gcov-9
}

git() {
    $SHELL -c "$GIT config --global core.autocrlf true"
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
# Prepare
capture ret prepare_globals
prepare_packages

########################################
# Get options
arguments=$(
    whiptail --title "Jiun's Settings" --separate-output --checklist "Selet options using arrow key and <TAB>" \
        32 80 11 \
        1. "Install default packages" on\
        2. "Change default locale [en_US]" on\
        3. "Install zsh and change default shell" on\
        4. "Install NeoVim/SpaceVim and set default editor" on\
        5. "Install tmux and change default config" on\
        6. "Install conda python and init conda" on\
        7. "[Optional] Install 'eza' to replace 'ls'" on\
        8. "[Optional] Install 'fzf': fuzzy finder" on\
        9. "[Optional] Install 'fd': alternative to 'find'" on\
        3>&1 1>&2 2>&3
)

########################################
# Install
for arg in $arguments; do
    case $arg in
    1.) 
        $( install_wrapper default_packages "Install default packages" )
        ;;
    2.)     
        $( install_wrapper change_locale "Change default locale [en_US]" )
        ;;
    3.) 
        $SUDOPREFIX $MANAGER install zsh $Y_FLAG > /dev/null 2>&1;
        $( install_wrapper zsh "Install zsh and change default shell" )
        ;;
    4.) 
        $SUDOPREFIX $MANAGER install neovim $Y_FLAG > /dev/null 2>&1;
        $( install_wrapper vim "Install Neo/SpaceVim and set default editor" )
        ;;
    5.) 
        $SUDOPREFIX $MANAGER install tmux $Y_FLAG > /dev/null 2>&1;
        $( install_wrapper tmux "Install tmux and change default config" )
        ;;
    6.) 
        $( install_wrapper conda "Install conda python and init conda" )
        ;;
    7.) 
        $( install_wrapper eza "Install 'eza' to replace 'ls'" )
        ;;
    8.) 
        $( install_wrapper fzf "Install 'fzf': fuzzy finder" )
        ;;
    9.)
        $( install_wrapper fd "Install 'fd': alternative to 'find'" )
        ;;
    *)
        echo "Invalid arguments"
        break
        ;;
    esac
    DRAFT=true
done

########################################
# Finalize
if [ $DRAFT = true ]; then
    echo "Installation completed, please restart your shell"
    echo "See also $LOG_FILE"
    if [[ -d "$TEMPDIR" ]]; then
        rm -r $TEMPDIR;
    fi
else
    echo "Installation canceled";
fi
