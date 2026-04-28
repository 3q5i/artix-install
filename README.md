# Artix-install

A TUI installer for Artix Linux with dinit, openrc, runit and s6 that aims to give you a minimal and bloat-free system without sacrificing convenience.

## Why would I choose this over the official installer?

-It gives you the customization of the manual install while making it easy

## What it configures
- Disk partitioning and filesystem (ext4, btrfs, xfs, f2fs and more)
- Kernel ( zen, lts, standard and custom kernels like cachyos and liquorix kernel)
- Bootloader (GRUB, Limine, rEFInd)
- Swap (zram, swapfile, both or neither)
- CPU microcode and GPU drivers 
- Keyboard layout, locale, timezone
- Audio via PipeWire for desktop environments
- doas or sudo
- also it lets you choose between xlibre and xorg
- WiFi (carries your live session connection into the install if youre going to use network manager)
- Repos ( as in it lets you enable 32 bit support and add the cachyos repos with their kernel)
- DE/WM(you can also pick cli dont worry): Cosmic(perfomance issues), KDE Plasma, XFCE, LXQt, Hyprland, Moksha, i3, XMonad,Icewm and Fluxbox 

# Usage
Boot the Artix live ISO(please use the weekly release the stable one is broken), connect to wifi via nmtui, then run the following command as root

### for the stable release 

```
curl -sL https://raw.githubusercontent.com/feribsd/artix-install/main/artix-install.sh | bash
```

### or if you want the testing one run this command instead(note that it can just break)

```
curl -sL https://raw.githubusercontent.com/feribsd/artix-install/main/artix-install-testing.sh | bash
```


Then just go through the installer it is fairly simple and sit back and relax.


## Things to add/fix
- [ * ] s6 and runit(now avalible in the testing release but I suggest you wait for now since well its testing)
- [ ] add MORE wms
- [ ] add a option to prerice your wm
- [ ] fix the cosmic performance problem
- [ ] galaxy repos option next to the lib32
- [ ] enable arch repo support from the installer
- [ ] let users install packages from the installer
- [ ] let the user enter chroot from the installer at the end of the installation 
- [ ] step by step guide
