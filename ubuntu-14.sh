#!/bin/bash

set -e
set -x

# Bootstraps Ubuntu 14.04 lts
# Installs minimal stuff to enable ansible-pull
# Usage: curl -sSL https://<this file's url> | sh -s <repo> <branch> <tags> <deploy key>
# (c) Copyright 2016, Dmitry Ulupov

if [ -z "$4" ]; then
    echo "CRITICAL ERROR: not enough arguments. Usage: $0 <repo> <branch> <tags> <deploy key>"
    exit 1
fi

REPO=$1
BRANCH=$2
TAGS=$3
KEY=$4

set -u

ANSIBLE_KEY_FILE=/etc/deploy.key
ANSIBLE_CLONE_DIR=/tmp/ansible-pull-clone
ANSIBLE_PULL=/usr/bin/ansible-pull
METASO_ANSIBLE_PULL_SCRIPT=/etc/metaso-ansible-pull.sh
METASO_ANSIBLE_PULL_CRON=/etc/cron.d/metaso-ansible-pull
METASO_ANSIBLE_PULL_LOCK=/tmp/metaso-ansible.lock

export DEBIAN_FRONTEND=noninteractive
apt-get -qq update
apt-get -qqy install python-pip python-dev software-properties-common build-essential git bc jq nano at libffi-dev libssl-dev

pip -q install awscli
pip install ansible==2.3.2
cp -v -s /usr/local/bin/ansible* /usr/bin/

# This should fix this error: InsecurePlatformWarning: A true SSLContext object is not available.
# pip install --upgrade 'requests[security]'
# ... but it does not

# This removes exit 0 from rc.local
sed -i.original-backup '/exit 0/d' /etc/rc.local

# Install key to access ansible-pull repo
# Key comes as base64 encoded string (AWS CloudFormation friendly)

echo ${KEY} | base64 --decode > ${ANSIBLE_KEY_FILE}
chmod 600 ${ANSIBLE_KEY_FILE}

cat > ${METASO_ANSIBLE_PULL_SCRIPT} <<END
#!/bin/bash
export PYTHONUNBUFFERED=1
flock -x -n ${METASO_ANSIBLE_PULL_LOCK} ${ANSIBLE_PULL} --checkout=${BRANCH} --accept-host-key --directory=${ANSIBLE_CLONE_DIR} --sleep=60 --url ${REPO} --private-key=${ANSIBLE_KEY_FILE} -t ${TAGS}
END

chmod 0755 ${METASO_ANSIBLE_PULL_SCRIPT}

# Install ansible-pull into cron
cat > ${METASO_ANSIBLE_PULL_CRON} <<END
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/20 * * * * root ${METASO_ANSIBLE_PULL_SCRIPT} 2>&1 |logger -t ansible-pull
END

service cron restart
