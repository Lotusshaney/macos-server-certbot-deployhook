#!/bin/bash

# deploy script for macOS + Server, inspired by JeffTheRocker on
# the Letsencrypt community

# Copyright ©2019 Gerben Wierda. All Rights Reserved
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 1. Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
# 3. The name of the author may not be used to endorse or promote products
# derived from this software without specific prior written permission.

# THIS SOFTWARE IS PROVIDED BY [LICENSOR] "AS IS" AND ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
# EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
# BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER
# IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

# Version 1.0 2018-10-11 Gerben Wierda
# Version 1.01 2018-10-14 Gerben Wierda
# Version 1.02 2018-10-27 Gerben Wierda
# Version 1.03 2018-11-05 Gerben Wierda
# Version 1.04 2019-02-23 Gerben Wierda
# Version 1.05 2019-02-27 Gerben Wierda
VERSION="v1.05"

# NOTE: this script may remove identities that are related to the domain
# being installed/renewed (keys & certs) from the System keychain if the
# identity is no longer in use by Server.app. This is limited to identities
# that cover the domain name being updated/renewed only.
# It will thus remove identities that may be in use without Server.app being
# aware of them. DANGER! This may be unsafe on Mojave+ Server 5.7+ or in any
# situation where there are identities managed by certbot in use outside of
# Server.app's knowledge.
# Uncomment the next line to live dangerously (but useful if it applies to you):
MODE="REMOVE"
# Use at your own risk.

# This script should be executable and run as root

# Examples (all with force renewal, this is not normal usage):
# sudo certbot certonly --force-renewal \
#   --webroot -w /Library/Server/Web/Data/Sites/www.example.com \
#   -d www.example.com,foo.example.com \
#   --deploy-hook <LOCATIONOFTHISSCRIPT>/certbot-macosserver-deploy.sh
# Or install in directory /etc/letsencrypt/renewal-hooks/deploy and:
# sudo certbot certonly --force-renewal \
#   --webroot -w /Library/Server/Web/Data/Sites/www.example.com \
#   -d www.example.com
# Or install anywhere else and (2 commands):
# sudo certbot certonly --force-renewal \
#   --webroot -w /Library/Server/Web/Data/Sites/www.example.com \
#   -d www.example.com
# <LOCATIONOFTHISSCRIPT>/certbot-macosserver-deploy.sh www.example.com

# Actual normal use:
# 1. Install as /etc/letsencrypt/renewal-hooks/deploy/certbot-macosserver-deploy.sh
#    and it will be automatically run by certbot after installation of a new cert
# 2. Run once by hand to install the cert the first time (example for two domains):
#        sudo certbot certonly \
#            --webroot -w /Library/Server/Web/Data/Sites/www.example.com \
#            -d www.example.com,foo.example.com
#    This installs the cert for the first time
# 3. Add a line to the root crontab, such as
#        10 5 * * * /usr/local/bin/certbot renew >>/var/log/certbot.log 2>&1
#    This keeps your cert valid. Renewal is logged in /var/log/certbot.log
#    (which technically will grow endlessly, so for perfection, this log file should be trimmed)

# The actual script starts here

# Dat format for logging/output
DATE=$(date +"%C%y-%m-%d_%H:%M:%S")
SCRIPT=$0
LOGLABEL="${SCRIPT} (${VERSION}) [${DATE}]"

if [ "$(whoami)" != "root" ]; then
    echo "${LOGLABEL}: This script should be run as root."
    exit 1
fi

DARWINVERSION=`uname -r | sed 's/\..*//'`
if [ ${DARWINVERSION} -le 16 ]
then
    echo "${LOGLABEL}: This older version of macOS (Darwin ${DARWINVERSION}) is untested. It might work."
    echo "${LOGLABEL}: You can let it proceed anyway by commenting out this and following messages and the exit command after these messages in the script."
    echo "${LOGLABEL}: If it works, let me know at gerben.wierda@rna.nl. Exiting..."
    exit 1
fi
if [ ${DARWINVERSION} -gt 17 ]
then
    echo "${LOGLABEL}: This version of macOS (Darwin ${DARWINVERSION}) is not supported. It will not work. Exiting..."
    exit 1
fi

if (ps x|grep '/Applications/Server.app/'|grep -v grep>/dev/null 2>&1)
then
    echo "${LOGLABEL}: Server is running on this system. Proceeding..."
fi

# A commandline argument overrides inheriting the domain from the environment
# normally, when this is run as --deploy-hook for certbot, the domain name is
# passed via the environment

# If certbot was called for multiple domains, the first one is the certs main
# identity as used in Server.app, the others are aliases

if [ "$1" != "" ]
then
    # If used with command line argument: use these instead of what would be
    # inherited from certbot
    # Second argument is the override for ORIGINALIDENTITY (the one to be
    # removed at the end as it is no longer in use)
    DOMAINS=($1)
    DOMAIN=${DOMAINS[0]}
    PEM_FOLDER="/etc/letsencrypt/live/${DOMAIN}"
else
    DOMAINS=(${RENEWED_DOMAINS})
    DOMAIN=${DOMAINS[0]}
    PEM_FOLDER=${RENEWED_LINEAGE}
fi

# Uncomment if you want to be talkative
echo "${LOGLABEL}: Install in macOS Server for ${DOMAINS} from ${PEM_FOLDER}"

# Minimal check on valid arguments and environment
if [ "${DOMAINS}" = "" -o ! -d "${PEM_FOLDER}" ]
then
    echo "${LOGLABEL}: No domains given or the certificate folder for domain \"${DOMAINS}\" does not exist. Exiting..."
    exit 1
fi

# Actual work:

# Find out if the certificate for this domain is used by Server.app
# This is done by backtick command to get the value out of a subshell
# (I wish I had written this in python in the first place)
ORIGINALIDENTITY=`security find-identity -p ssl-server -s "${DOMAIN}" \
    /Library/Keychains/System.keychain | \
    awk 'BEGIN {FS = "[ \"]"} { if (length($4) == 40) print $6 " " $4}' | \
while read i ;\
do \
    if [ "${i% *}" = "${DOMAIN}" ] ;\
    then \
        if (/Applications/Server.app/Contents/ServerRoot/usr/sbin/serveradmin settings all | grep "${DOMAIN}.${i#* }" >/dev/null 2>&1) ;\
	then \
            echo -n "${i#* }" ;\
	    break ;\
	    fi ;\
    fi ;\
done`

if [ "${ORIGINALIDENTITY}" == "" ]
then
    echo "${LOGLABEL}: There is currently no identity for ${DOMAIN}, a new one will be created and needs to be linked by hand (once) to the service(s)"
else
    if [ "${MODE}" = "REMOVE" ]
    then
	echo "${LOGLABEL}: Identity ${ORIGINALIDENTITY} is currently in use by Server.app for ${DOMAIN}. It will be removed afterwards."
    else
	echo "${LOGLABEL}: Identity ${ORIGINALIDENTITY} is currently in use by Server.app for ${DOMAIN}"
    fi
fi

if [ "$2" != "" ]
then
    ORIGINALIDENTITY=$2
    echo "${LOGLABEL}: Using 2nd arg for OriginalIdentity override ${ORIGINALIDENTITY}"
fi

# Add the key to the System keychain for Server.app which will automatically
# apply it

# Generate a passphrase
PASS=$(openssl rand -base64 45 | tr -d /=+ | cut -c -30)

# Transform the pem files into a OS X Valid p12 file
openssl pkcs12 -export \
    -inkey "${PEM_FOLDER}/privkey.pem" \
    -in "${PEM_FOLDER}/cert.pem" \
    -certfile "${PEM_FOLDER}/fullchain.pem" \
    -out "${PEM_FOLDER}/letsencrypt_sslcert.p12" \
    -passout pass:$PASS

# import the p12 file in keychain
security import "${PEM_FOLDER}/letsencrypt_sslcert.p12" -f pkcs12 \
    -k /Library/Keychains/System.keychain \
    -P $PASS \
    -T /Applications/Server.app/Contents/ServerRoot/System/Library/CoreServices/ServerManagerDaemon.bundle/Contents/MacOS/servermgrd

# Give the system time to finish reconfiguring services

# Find out if the original certificate for this domain is still used by
# Server.app
# serveradmin may take some time to reflect the new reality, therefore, as
# long as serveradmin still reports the old identity in use for the domain
# it is still not done. We build a loop of 10 tries to wait for serveradmin
# to complete its work.
for ((j=1; j<11; j++))
do
    echo "${LOGLABEL}: Checking ${DOMAIN}.${ORIGINALIDENTITY} for usage (try $j of 10)"
    if /Applications/Server.app/Contents/ServerRoot/usr/sbin/serveradmin settings all | grep "${DOMAIN}.${ORIGINALIDENTITY}" >/dev/null 2>&1
    then
	echo "${LOGLABEL}: Serveradmin is not yet done configuring to use the new identity. Waiting 6 seconds and retrying..."
	sleep 6
    else
	echo "${LOGLABEL}: ${ORIGINALIDENTITY} is not/no longer part of serveradmin's settings. Proceeding..."
	break
    fi
done
if [ $j -eq 11 ]
then
    # This happens for instance when switching from certbot --staging to certbot. In that case
    # you need to set the certificate by hand in Server.app
    # It also happens when you go from a single-domain cert to multiple-domain
    echo "${LOGLABEL}: ${ORIGINALIDENTITY} is still part of serveradmin's settings. The certificate was apparently not automatically replaced. Manual intervention necessary."
fi

security find-identity -p ssl-server -s "${DOMAIN}" \
	/Library/Keychains/System.keychain | \
    awk 'BEGIN {FS = "[ \"]"} { if (length($4) == 40) print $6 " " $4}' | sort | uniq | \
while read i
do
    IDENTITY="${i#* }"
    if /Applications/Server.app/Contents/ServerRoot/usr/sbin/serveradmin settings all | grep "${i#* }" >/dev/null 2>&1
    then
	echo "${LOGLABEL}: Identity ${IDENTITY} is in use by Server.app for ${i% *}. It will not be removed."
    else
	if [ "${IDENTITY}" = "${ORIGINALIDENTITY}" ]
	then
	    if [ "${MODE}" = "REMOVE" ]
	    then
		echo "${LOGLABEL}: Identity ${ORIGINALIDENTITY} is no longer in use by Server.app. Removing..."
		security delete-identity -Z "${ORIGINALIDENTITY}" /Library/Keychains/System.keychain
	    else
		echo "${LOGLABEL}: Identity ${ORIGINALIDENTITY} is no longer in use by Server.app. It should probably be removed."
	    fi
	else
	    echo "${LOGLABEL}: Identity ${IDENTITY} is not in use by Server.app. It should probably be removed."
	fi
    fi
done
exit 0
