Starting Here: <ins>https://gist.github.com/verticalgrain/deae2821213a891747e08e2d6492808a</ins>

1.  I retrieved my build/image from here: <ins>http://chip.jfpossibilities.com/chip/images/stable/</ins>
    
    1.  I used the GUI image, just to see it work visually, but if you have the pocket chip add on, use that, or if you want the server version use that, etc.
        
    2.  I placed all the image files into a folder named `stable-gui-b149`
        
2.  I downloaded the `CHIP-SDK` zip file from here: <ins>https://github.com/Project-chip-crumbs/CHIP-SDK</ins>
    
    1.  Unzip files, folder is named `CHIP-SDK-master`
3.  I downloaded the `CHIP-TOOLS` zip file from here: <ins>https://github.com/Project-chip-crumbs/CHIP-tools</ins>
    
    1.  Unzip files, folder is named `CHIP-tools-chip-stable`
4.  Move your image folder (stable-gui-b149) into the `CHIP-SDK-master` folder
    
5.  Move your `CHIP-tools-chip-stable folder` into the `CHIP-SDK-master` folder
    
6.  Open Terminal, `cd ~/Downloads/CHIP-SDK-master && ./setup_ubuntu1404.sh`
    
7.  This will set up the SDK. You will get some errors saying CHIP-tools is already installed, but possibly several others
    
    1.  Start with sudo apt update
        
    2.  To alleviate “git: command not found”
        
        1.  `sudo apt install git`
    3.  To alleviate “make: command not found”
        
        1.  `sudo apt install make`
    4.  To alleviate “make: cc: No such file or directory”
        
        1.  `sudo apt install build-essential`
            
        2.  `export CC=gcc`
            
    5.  To alleviate “/bin/sh: 1: pkg-config: not found”
        
        1.  `sudo apt install pkg-config`
    6.  To alleviate python related errors:
        
        1.  `Sudo apt install python-dev-is-python3`
            
        2.  `sudo apt nstall python3-pip`
            
    7.  To alleviate “fatal error libusb.h: no such file or directory”
        
        1.  `sudo apt install libusb-1.0-0-dev`
    8.  To alleviate “fatal error zlib.h: no such file or directory”
        
        1.  `sudo apt install zlib1g-dev`
    9.  To alleviate “fatal error libfdt.h: no such file or directory”
        
        1.  `sudo apt install libfdt-dev`
    10. To alleviate “Package android-tools-fsutils is not available….”
        
    11. `sudo apt install android-sdk-lib sparse-utils`
        
    12. To alleviate “Error: Unable to locate fastboot utility”
        
    13. `sudo apt install fastboot`
        
    14. To alleviate “Error: Unable to locate mkimage utility”
        
    15. `sudo apt install u-boot-tools`
        
8.  Next change directories to `CHIP-tools-chip-stable` with: `cd CHIP-tools-chip-stable`
    
9.  Open the following files: <ins>`chip-feel-flash.sh`</ins>, `chip-flash`, <ins>`common.sh`</ins>
    
    1.  search for “`-i 0x1f3a`” in all three files and remove that string
        
    2.  search for “`-u`” in all three files and remove that string (there is one “`-u`” that’s not near “`-i 0x13fa`”)
        
    3.  Save files and close
        
    4.  The reason for this is that newer package distributions aren't compatible with the older CHIP-Tools, there are other ways around this, but this was most straightforward.
        
10. Put your CHIP into FEL mode, by connecting the FEL pin to any GRD pin (FEL is located on the right side if the connectors are facing you and the USB port is facing up)
    
11. Connect your CHIP to Micro USB (it should be a data transfer Micro USB, you can tell the difference by the grooves on the sides of the pins. <ins>https://superuser.com/questions/1269449/identifying-data-transfer-micro-usb-cables-vs-charge-only-micro-usb-cables</ins>)
    
12. Run: `./chip-update-firmware.sh -L ../stable-gui-b149`
    
13. You should get an output that starts with == Local directory ….. ==, some other info, and then “waiting for fel …..OK” and then again “waiting for fel….OK” followed by NAND detected, some more info another “waiting for fel …OK”
    
14. In an ideal state you should then get “waiting for fastboot…..OK”
    
15. However if you don’t get the first “waiting for fel….OK”:
    
16. go to your VirtualBox Settings > Ports > USB > hit the + icon and select “Onda (unverified) V972 tablet in flashing mode \[02B3\]” (or similar device)
    
17. If you get past the all the “waiting for fel…..OK”s, but “Waiting for fastboot…..TIMEOUT” occurs:
    
18. go to your VirtualBox Settings > Ports > USB > hit the + icon and select “Allwinner Technology USB download gadget \[0215\]” (or similar device)
    
19. Then again run: ./chip-update-firmware.sh -L ../stable-gui-b149
    
20. You should get more info saying “Sending sparse ‘UBI’ 1/24 … until it gets through 24/24 and says FLASH VERIFICATION COMPLETE / CHIP is ready to roll!
    
21. Success!
    

Hope this is helpful for anyone who ran into a number of issues like myself.

EDIT: Thanks for calling out the awful formatting [u/insanemal](https://www.reddit.com/user/insanemal/), it was unreadable
