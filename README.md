# USB-autocopier
This is a script for Ubunut, but might be usable in many other Linux distros. It sets up tge system to automatically copy files into a specific USB drive whenever it connects.

To use it, open a terminal, make the script executable with 'chmod +x USB-autocopier.sh', and run it with ./USB-autocopier.sh . Both commands are to be executed in the directory of the file itself.

The script sets up a udev post in Ubunut (or other Linux distro). The udev post will make the system copy specified files into the USB disk. So basically, whenever you plug a specific USB drive into your computer, a specific file will be copied onto it.
I made this script to automatically copy my Keepass database onto a specific USB drive, just by plugging it into my computer.
