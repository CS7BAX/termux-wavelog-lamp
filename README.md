## **termux-wavelog-lamp**

Automated LAMP installer (Apache, MariaDB, PHP 8.2) to run Wavelog inside a Debian container (proot-distro) on Termux, including a watchdog, Adminer and phpSysInfo.

Wavelog is a web-based logging software for ham radio operators

(go see their sitg at https://www.wavelog.org/)

Features:

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
        
    -   Termux:API
        
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
    

-   Go to the root home directory (usually already /root).
    
-   Download the setup script:
    
    -   wget  [https://raw.github.com/CR7BAX/termux-wavelog-lamp/main/setup.sh](https://raw.githubusercontent.com/CR7BAX/termux-wavelog-lamp/main/setup.sh)
        
-   Make it executable:
    
    -   chmod +x setup.sh
        
-   Run the installer:
    
    -   ./setup.sh


