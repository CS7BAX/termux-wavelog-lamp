## ​## **termux-wavelog-lamp**
It is an installation script for a web server specifically designed and optimized to run the Wavelog logging software.

![setup](setup.png) ![qso](qso_logging-ELV4YxrR.jpg)

Wavelog is a web-based logging application designed for ham radio operators.
For more information, visit the official website: https://www.wavelog.org/

Is designed to run on Android smartphones and other Android-based devices by leveraging Termux and proot-distro.

LAMP refers to a classic web stack composed of Linux, Apache, MariaDB/MySQL and PHP, providing the foundation required to host and operate web applications reliably.

Automated LAMP installer to run Wavelog inside a Debian container (proot-distro) on Termux, including a watchdog, Adminer (https://www.adminer.org/) and phpSysInfo (https://phpsysinfo.github.io/phpsysinfo/).

## Key advantages:

-   Portability: Take your logging software with you anywhere, with or without Internet access.
    
-   Single point of configuration: Configure QRZ, QRZ CQ, Club Log, LOTW, eQSL and many other third-party services in one tool and in one place.
    
-   Server-side maintenance: Maintain your own server and update your files on your schedule and to your requirements.
    
-   Security and control: You retain full control over the server and can decide whether to expose it to the Internet or keep it completely private.

## Features:

 1. Installs and configures Apache, MariaDB and PHP 8.2 inside Debian (proot-distro) on Termux.​
 2. Downloads and deploys the official Wavelog repository into /var/www/html.
 3. Creates helper scripts to start and stop all services (Apache, MariaDB and watchdog).
 4. Includes menu options to install Adminer (database management) and phpSysInfo (system information).​
 5. Provides a Termux launcher command (wave) to open Debian, run the setup menu and keep the device awake while Wavelog is running.

## Step-by-step installation guide

1.  Install the required Android apps:
    

-   Install F-Droid from  [https://f-droid.org](https://f-droid.org/).
    
-   From F-Droid, install:
    
    -   Termux
        
    -   A terminal emulator launcher if needed (for example a shortcut app).
        

2.  Prepare Termux:
    

-   Open Termux and run:
    
    -   pkg update
        
    -   pkg upgrade
        
    -   pkg install proot-distro termux-api tmux openssh
        

3.  Install Debian with proot-distro:
    

-   In Termux, run:
    
    -   proot-distro install debian​
        

4.  Configure SSH access in Termux (optional but recommended):
    

-   Set a Termux password:
    
    -   passwd
        
-   Check your Termux username:
    
    -   whoami
        
-   Start the SSH server:
    
    -   sshd​
        

5.  Log into Debian:
    

-   From Termux, start the Debian container:
    
    -   proot-distro login debian​
        

6.  Download and run the installer inside Debian:
    

-   Go to the root home directory (usually already /root). And run:
    
    -   apt update
        
    -   apt upgrade
    - apt install wget
    
-   Download the setup script:
    
    -   wget  [https://raw.github.com/CS7BAX/termux-wavelog-lamp/main/setup.sh](https://raw.githubusercontent.com/CS7BAX/termux-wavelog-lamp/main/setup.sh)
        
-   Make it executable:
    
    -   chmod +x setup.sh
        
-   Run the installer:
    
    -   ./setup.sh

![setup](setup.png)

After launching the installation script, it is as simple as selecting steps 5 through 11 in the highlighted installation block within the script.

When you select option 7 to create the database, the credentials are predefined as follows: 

database name “wavelog” 
user “wavelog” 
password “wavelog”.

It is important to note that after selecting option 8 and downloading the Wavelog copy, you must first open the web page served by the installer and complete Wavelog’s initial configuration. 

## ***>>>Only after this first-time setup is finished should you return to the installation script and continue the remaining steps until the end<<<.***

It can also install the optional tools Adminer (to manage the Wavelog database directly via a web interface) and phpSysInfo (to monitor system metrics such as CPU, RAM and other resource usage).

After the installation is complete, you can select option 14 or 4 to exit the menu, then type “exit” to leave Debian and “exit” again to leave Termux. 

At this point everything is installed, and to start the server again you only need to type "wave" at the Termux prompt, which will launch Debian, run setup.sh and allow you to start the web server once more.

Note: This script and the files it generates are designed to serve the Wavelog web interface over a local IP address assigned by your router or by the Android hotspot. When the phone or Android device is used in mobile hotspot mode, the script automatically detects the current IP and, at the end of the menu, displays the exact URL where the Wavelog web page is being served.

{Tested on Samsung J5 (SM- J510FN) and Xiaomi Redmi Note 10 Pro (M2101k6G)}


