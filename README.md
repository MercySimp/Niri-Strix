Arch Niri Strix

IN DEV RAMBLINGS 
This is just a pet project that is heavily inspired by omarchy, as omarchy is just a hyprland rice for Arch. So I thought why not do the same for Niri? 
Then came the question of why even ever use this versus any other option? Which comes down to me being gaming.
Every version I find is heavily inclusive of coding and programing apps, I don't really need those for my use case. I want yay, steam, lutris, wine, retroarch etc.
So that is where this came to be as I felt since I like my flavor of Arch maybe someone else might to. 

Strix uses linux-zen as the kernel, limine as the bootloader, btrfs for file structure, and the skew of packages listed in the package file. There are also some other hard coded values but they might become variables in later versions.

The first step was replication, build an ISO, then to build an install script which I felt would be easiest by passing a json file to archinstall. So that is what is currently being worked on, passing a json to archinstall.

This is still under heavily development and I only work on this when not doing my day job so hope to have a functioning version by end of the month but no clue.

The installer script is at 95% as it will currently install the system and not throw any flags moving all the config files from this github to the final live install. The next step is fixing some issues, A.) Archinstall takes the password exactly as it is passed by the installer, which is plaintext making the user unable to log in. Got around by setting the password in chroot and then booting. Other issue was that the boot files weren't created for limine so couldn't boot, fixed by reinstalling linux-zen as chroot. Running more tests, to resolve this before setting as beta version for install.

Fixed password issue by sending it prehashed password with yescrypt so whois was added just in case it wasn't installed already. The boot issue I feel probably is related to linux-zen being in my base packages along with being preinstalled by Archinstall so removed it from base packages since see no reason to keep it there on top of the install in chroot. 

But yea think it is all working now, about to run a new test with additional configs on top of adding in some bin files that I rebuilt from omarchy. Hoping all works.
