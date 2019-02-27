# macOS-Server-certbot-deployhook

Script to have automatic (clean) deployment of renewed letsencrypt certificates

This script should be installed as

/etc/letsencrypt/renewal-hooks/deploy/certbot-macosserver-deploy.sh

on macOS Server. Permissions should be set to 755.

If you now run (as root)

certbot renew

(or on any install of a new cert), this script will automatically run if a new
certificate has been installed. It will correctly install the new cert in 
Server Admin and the System Keychain. It will remove the previous cert if it
is no longer in use by Server Admin.

If you have the following in your root crontab:

? ? * * * /usr/local/bin/certbot -n renew >>/var/log/certbot.log 2>&1

(replace question marks with minute-of-the-hour and hour you want certbot to
attempt to renew), it will run once a day, and when a certificate has been
renewed, it will installed.

See the script itself for more documentation.