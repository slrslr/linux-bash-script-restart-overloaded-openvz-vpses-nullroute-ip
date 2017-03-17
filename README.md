# linux-bash-script-restart-overloaded-openvz-vpses-nullroute-ip
Linux bash script for the OpenVZ host server
Script should be run as a cronjob (probably minutely or even more frequently) to check OpenVZ VPSs if they are not overloaded (high load average) (DoSed etc.). If there is too high load average, nullroute VPS IP and if it does not help, restart VPS.
