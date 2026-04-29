# Artix-install

A TUI installer written in bash for Artix Linux that aims to give you a minimal and tailored system without sacrificing convenience.

## Why would I choose this over the official installer?

-It gives you the customization of the manual install while making it easy

## What it configures
- Disk partitioning and filesystem (ext4, btrfs, xfs, f2fs and more)
- Kernel (standard, lts, zen and custom kernels like cachyos, liquorix kernel and now in testing the XanMod which gets pulled from the aur)
- Bootloader (GRUB, Limine, rEFInd)
- Swap (zram, swapfile, both or neither)
- CPU microcode and GPU drivers 
- Keyboard layout, locale, timezone
- Audio via PipeWire for desktop environments
- doas or sudo
- also it lets you choose between xlibre and xorg
- WiFi (carries your live session connection into the install if youre going to use network manager)
- aur(yay,paru or none) - availbe in testing
- Repos (lets you enable 32bit ones arch support cachyos and repos galaxy repos) -avalibe in testing
- DE/WM(you can also pick cli dont worry): Cosmic(perfomance issues), KDE Plasma, XFCE, LXQt, Hyprland, Moksha, i3, XMonad,Icewm and Fluxbox 

# Known issues
- some isps block the script from being executed for some reason that reportedly happen to one of my testers so yeah idk try git cloning it or something
- Cosmic has an performance problem due to the elogind not communticating properly at least I think thats the issue your cpu will just get pinned at 99%
- yay with doas is finicky
- stable release of the iso doesnt work with this installer

# Usage
1. Dowload the WEEKLY iso release NOT THE STABLE one from the artix linux site
https://artixlinux.org/download.php

3. Flash your iso iam going to use dd as an example you can also use ventoy,balena etcher, rufus, popsicle etc.
```
dd if=pathtoyouriso of=/dev/sdX bs=4M status=progress oflag=sync
```


3. Boot your iso login is root password is artix and then run Netowork manager to connect to wifi with an user frindly tui
 
 ```
 nmtui
 ```
4. And the last step is curling the script 

### for the stable release 

```
curl -sL https://raw.githubusercontent.com/feribsd/artix-install/main/artix-install.sh | bash
```

### or if you want the testing one run this command instead(note that since its not tested all that well it can break )

```
curl -sL https://raw.githubusercontent.com/feribsd/artix-install/main/artix-install-testing.sh | bash
```


Then just go through the installer it is fairly simple and sit back and relax.


## Things to add
- [ ] add MORE wms
- [ ] add a option to prerice your wm
- [ ] video tutorial

