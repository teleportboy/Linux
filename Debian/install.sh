#!/bin/bash

set -o errexit
SCRIPT_PATH="$(dirname -- "${BASH_SOURCE[0]}")"

# System
sudo apt install xinit curl git build-essential xsel arandr software-properties-common baobab htop doublecmd-qt rxvt-unicode apt-transport-https x11-utils -y
# font JetBrains
sudo apt install fonts-jetbrains-mono -y
# cursor. if user's choice needed - sudo update-alternatives --config x-cursor-theme
sudo apt install breeze-cursor-theme -y
sudo update-alternatives --set x-cursor-theme /etc/X11/cursors/Breeze_Snow.theme


# VMware
case $(systemd-detect-virt) in
  vmware)
    sudo apt install open-vm-tools open-vm-tools-desktop -y
    # VMware MacBook 14''. RESOLUTION FIX
    #   Notch: 74pixels. VMWare fullscreen ratio 1.6
    #   xrandr --listactivemonitors should be Virtual-1 in VMware
    # echo 'cvt 1760 1100' >> ~/.xprofile
    # echo 'xrandr --newmode "1760x1100_60.00"  160.75  1760 1872 2056 2352  1100 1103 1109 1141 -hsync +vsync' >> ~/.xprofile
    # echo 'xrandr --addmode Virtual-1 "1760x1100_60.00"' >> ~/.xprofile
    # echo 'xrandr --output Virtual-1 --mode 1760x1100_60.00' >> ~/.xprofile
    # echo '[ -f /etc/xprofile ] && . /etc/xprofile' >> ~/.xinitrc
    # echo '[ -f ~/.xprofile ] && . ~/.xprofile' >> ~/.xinitrc
    ;;
  *)
    # TLP
    # https://linrunner.de/tlp/index.html
    sudo apt install tlp tlp-rdw -y
    # TLP UI
    # https://github.com/d4nj1/TLPUI
    sudo add-apt-repository -y ppa:linuxuprising/apps
    sudo apt update
    sudo apt install tlpui
    sudo tlpui
    ;;
esac


# URxvt
sudo apt install rxvt-unicode -y


# Configure keyboard
sudo apt install keyboard-configuration
sudo apt install console-setup
sudo dpkg-reconfigure keyboard-configuration
sudo service keyboard-setup restart
# restart kernel input system via udev
sudo udevadm trigger --subsystem-match=input --action=change


# ZSH
sudo apt install zsh -y
sudo chsh -s /bin/zsh $(whoami)
echo "unsetopt inc_append_history" >> ~/.zshrc
echo "unsetopt share_history" >> ~/.zshrc
echo "PATH=$PATH:/usr/sbin" >> ~/.zshrc
# manual change shell
#sudo nano /etc/passwd
zsh


# OhMyZSH
# https://github.com/ohmyzsh/ohmyzsh
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
omz update
sed -i 's/_THEME=\"robbyrussell\"/_THEME=\"agnoster\"/g' ~/.zshrc


# i3
# https://i3wm.org/
sudo apt install i3 -y
startx
# Xresources
cat << EOF >> ~/.Xresources
URxvt.scrollstyle: xterm
URxvt.scrollBar: false
URxvt.secondaryScreen: 1
URxvt.secondaryScroll: 0
URxvt.secondaryWheel: 1
URxvt.font: xft:JetBrainsMono-Medium:size=10
URxvt.letterSpace: 0
URxvt.cursorBlink: false
URxvt.colorUL: #4682B4
URxvt.foreground: #EAEAEA
URxvt.background: #1E1E1E
URxvt.clipboard.autocopy: true
URxvt.iso14755: false
URxvt.iso14755_52: false
EOF
# i3 close shortcut change
sed -i 's/$mod+Shift+q/$mod+q/g' ~/.config/i3/config
# i3 term change
sed -i "s/i3-sensible-terminal/urxvt/g" ~/.config/i3/config
# xinit 
echo 'xrdb merge ~/.Xresources' >> ~/.xinitrc
echo 'exec i3' >> ~/.xinitrc


# Powerline
# https://github.com/powerline/powerline
sudo apt install powerline -y
cp -r /usr/share/powerline/config_files ~/.config/powerline
echo "if [[ -r /usr/share/powerline/bindings/zsh/powerline.zsh ]]; then" >> ~/.zshrc
echo "source /usr/share/powerline/bindings/zsh/powerline.zsh" >> ~/.zshrc
echo "fi" >> ~/.zshrc


# Poylybar
# https://github.com/polybar/polybar
sudo apt install polybar -y
sudo apt install pulseaudio -y
# config.ini
mkdir -p ~/.config/polybar
cp $SCRIPT_PATH/.config/polybar/config.ini ~/.config/polybar/config.ini
# launch.sh
cat << EOF >> ~/.config/polybar/launch.sh
#!/usr/bin/zsh
killall -q polybar
echo "---" | tee -a /tmp/polybar.log
polybar default 2>&1 | tee -a /tmp/polybar.log & disown
echo "Bar launched..."
EOF
chmod +x ~/.config/polybar/launch.sh
# remove i3 bar
sed -i '/^bar {/,/}/d' ~/.config/i3/config
# add launch.sh to i3
echo "exec_always --no-startup-id $HOME/.config/polybar/launch.sh" >> ~/.config/i3/config

