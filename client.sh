#!/bin/bash

function check_if_docker () {
    if $(docker --help > /dev/null 2>&1); then
        echo "Docker installed, proceeding"
    else
        echo "Docker Client is not installed, please install it"
        exit 0
    fi
}
function gen_alphanumeric () {
    if [ "$1" == "" ]; then
        echo $(tr '-dc A-Za-z0-9_' </dev/urandom | head -c 13 ; echo '')
    else
        echo $(tr '-dc A-Za-z0-9_' </dev/urandom | head -c $1 ; echo '')
    fi
}

function get_input () {
    echo "You will now be asked for information to help us configure your system for docker compose. Press enter to use the default value in []. Press enter when ready to proceed."
    read -p 'Host / IP: ' HOST_OR_IP
    read -p 'SSH Username [root]: ' SSH_USER
    SSH_USER=${SSH_USER:-root}
    read -p 'SSH Port [22]: ' PORT
    SSH_PORT=${SSH_PORT:-22}
    read -p 'Main Domain: ' DOMAIN
    read -p 'Do you want a staging env - recommended [y]: ' STAGING
    STAGING=${STAGING::-y}
    AUTO_CHECK=$(echo "${STAGING:0:1}" | tr '[:upper:]' '[:lower:]')
    if [ "$STAGING" == "y" ]; then
        STAGING=true
    else
        STAGING=false
    fi
    read -p 'Discord Token (https://www.writebots.com/discord-bot-token/): ' DISCORD_TOKEN
    if $STAGING; then
        read -p 'Staging Discord Token (enter same token as prod if you do not have a staging Discord server): ' STAGING_DISCORD_TOKEN
    fi
    read -p 'Cloudflare Email Address: ' CF_EMAIL
    read -p 'Cloudflare API Key (needs DNS access) (https://developers.cloudflare.com/api/tokens/create/): ' CF_API_KEY
    read -p 'Would you like me to generate all remaining parameters (datatabase name, DB & Grafana username, DB & Grafana pass, and HTPASSWD values)? (y/n)' AUTO
    AUTO_CHECK=$(echo "${AUTO:0:1}" | tr '[:upper:]' '[:lower:]')
    if [ "$AUTO" == "y" ]; then
        DB_NAME=gen_alphanumeric 4
        DB_NAME="dbn_$DB_NAME"
        DB_USER=gen_alphanumeric 4
        DB_USER="dbu_$DB_USER"
        DB_PASS=gen_alphanumeric
        DB_ROOT_PASS=gen_alphanumeric
        GRAFANA_USER=gen_alphanumeric 4
        GRAFANA_USER="graf_$GRAFANA_USER"
        GRAFANA_PASS=gen_alphanumeric
        HT_USER=gen_alphanumeric 4
        HT_USER="ht_$HT_USER"
        HT_PASS=gen_alphanumeric
        if $STAGING; then
            STAGING_PREFIX=gen_alphanumeric 4
            DB_STAGING_PASS="STAGING_PREFIX_$DB_PASS"
            DB_STAGING_ROOT_PASS="STAGING_PREFIX_$DB_ROOT_PASS"
            DB_STAGING_PORT=3307
        fi
    else
        read -p 'DB Name: ' DB_NAME
        read -p 'DB User: ' DB_USER
        read -p 'Prod DB Password: ' DB_PASS
        read -p 'Prod DB Root Password: ' DB_ROOT_PASS
        read -p 'Grafana User: ' GRAFANA_USER
        read -p 'Grafana Password: ' GRAFANA_PASS
        read -p 'HTTP User: ' HT_USER
        read -p 'HTTP Password: ' HT_PASS
        if $STAGING; then
            read -p 'Staging environment prefix (the string that gets prepended to staging vars): ' STAGING_PREFIX
            read -p 'Staging DB Port: ' DB_STAGING_PORT
        fi
    fi
    ENC_HTPASS=$(openssl passwd -apr1 $HT_PASS)
}

function ssh_key_and_config () {
    echo "Saving host key fingerprint"
    KNOWN_HOSTS=$(ssh-keyscan -H $HOST_OR_IP)
    echo "$KNOWN_HOSTS" >> ~/.ssh/known_hosts
    echo "Generating SSH Keypair"
    ssh-keygen -t rsa -b 4096 -C "docker_compose_client_script" -N "" -f ~/.ssh/docker_compose_host
    echo "Adding new key to remote server"
    PUB_KEY=$(cat ~/.ssh/docker_compose_host.pub)
    ssh $HOST_OR_IP -l $SSH_USER -p $PORT "echo $PUB_KEY >> ~/.ssh/authorized_keys"
    echo "Setting SSH to use the generated keys in the future and backing up old SSH config"
    cp ~/.ssh/config ~/.ssh/config.bak
    echo "Host docker-compose
        HostName $HOST_OR_IP
        User     $SSH_USER
        IdentityFile       ~/.ssh/docker_compose_host
        
    Host $HOST_OR_IP
        User     $SSH_USER
        IdentityFile       ~/.ssh/docker_compose_host" > ~/.ssh/config
}

function install_config_packages () {
    echo "Installing Docker engine"
    ssh $HOST_OR_IP -l $SSH_USER -p $PORT "yum install -y yum-utils"
    ssh $HOST_OR_IP -l $SSH_USER -p $PORT "yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo"
    ssh $HOST_OR_IP -l $SSH_USER -p $PORT "yum install docker-ce docker-ce-cli containerd.io wget fail2ban -y"
    echo "Downloading Node Exporter"
    ssh $HOST_OR_IP -l $SSH_USER -p $PORT "wget https://github.com/prometheus/node_exporter/releases/download/v1.3.1/node_exporter-1.3.1.linux-amd64.tar.gz"
    echo "Extracting Node Exporter"
    ssh $HOST_OR_IP -l $SSH_USER -p $PORT "tar -xzf node_exporter*"
    echo "Adding user for node_exporter"
    ssh $HOST_OR_IP -l $SSH_USER -p $PORT "useradd -rs /bin/false node_exporter"
    echo "Moving node exporter to system install location"
    ssh $HOST_OR_IP -l $SSH_USER -p $PORT "mv -f node*/node_exporter /usr/local/bin"
    echo "Creating service for node exporter"
    ssh $HOST_OR_IP -l $SSH_USER -p $PORT 'echo "[Unit]
    Description=Node Exporter
    After=network.target

    [Service]
    User=node_exporter
    Group=node_exporter
    Type=simple
    ExecStart=/usr/local/bin/node_exporter

    [Install]
    WantedBy=multi-user.target" > /etc/systemd/system/node_exporter.service'
    echo "Reloading, starting, checking status and enabling node exporter on startup"
    ssh $HOST_OR_IP -l $SSH_USER -p $PORT "systemctl daemon-reload"
    ssh $HOST_OR_IP -l $SSH_USER -p $PORT "systemctl start node_exporter"
    ssh $HOST_OR_IP -l $SSH_USER -p $PORT "systemctl status node_exporter"
    ssh $HOST_OR_IP -l $SSH_USER -p $PORT "systemctl enable node_exporter"
    ssh $HOST_OR_IP -l $SSH_USER -p $PORT "systemctl start docker"
    ssh $HOST_OR_IP -l $SSH_USER -p $PORT "systemctl start fail2ban"
    ssh $HOST_OR_IP -l $SSH_USER -p $PORT "docker plugin install grafana/loki-docker-driver:latest --alias loki --grant-all-permissions"
    ssh $HOST_OR_IP -l $SSH_USER -p $PORT "sed -i /etc/ssh/sshd_config 's/#MaxSessions 10/MaxSessions 30/g"
    ssh $HOST_OR_IP -l $SSH_USER -p $PORT "systemctl restart sshd"
}

function configure_local () {
    find . \( -type d -name .git -prune \) -o -type f ! -name client.sh -print0 | xargs -0 sed -i "s/REPLACE_ME_DISCORD_TOKEN/$DISCORD_TOKEN/g"
    find . \( -type d -name .git -prune \) -o -type f ! -name client.sh -print0 | xargs -0 sed -i "s/REPLACE_ME_DB_NAME/$DB_NAME/g"
    find . \( -type d -name .git -prune \) -o -type f ! -name client.sh -print0 | xargs -0 sed -i "s/REPLACE_ME_DB_USER/$DB_USER/g"
    find . \( -type d -name .git -prune \) -o -type f ! -name client.sh -print0 | xargs -0 sed -i "s/REPLACE_ME_DB_USER_PASS/$DB_PASS/g"
    find . \( -type d -name .git -prune \) -o -type f ! -name client.sh -print0 | xargs -0 sed -i "s/REPLACE_ME_DB_ROOT_PASS/$DB_ROOT_PASS/g"
    find . \( -type d -name .git -prune \) -o -type f ! -name client.sh -print0 | xargs -0 sed -i "s/REPLACE_ME_DOMAIN/$DOMAIN/g"
    find . \( -type d -name .git -prune \) -o -type f ! -name client.sh -print0 | xargs -0 sed -i "s/REPLACE_ME_CF_EMAIL/$CF_EMAIL/g"
    find . \( -type d -name .git -prune \) -o -type f ! -name client.sh -print0 | xargs -0 sed -i "s/REPLACE_ME_CF_DNS_API_TOKEN/$CF_API_KEY/g"
    find . \( -type d -name .git -prune \) -o -type f ! -name client.sh -print0 | xargs -0 sed -i "s/REPLACE_ME_WEB_AUTH_USER/$HT_USER/g"
    find . \( -type d -name .git -prune \) -o -type f ! -name client.sh -print0 | xargs -0 sed -i "s/REPLACE_ME_WEB_AUTH_BCRYPT_PASSWORD/$ENCHT_PASS/g"
    find . \( -type d -name .git -prune \) -o -type f ! -name client.sh -print0 | xargs -0 sed -i "s/REPLACE_ME_GRAFANA_USER/$GRAFANA_USER/g"
    find . \( -type d -name .git -prune \) -o -type f ! -name client.sh -print0 | xargs -0 sed -i "s/REPLACE_ME_GRAFANA_PASS/$GRAFANA_PASS/g"
    
    if $STAGING; then
        find . \( -type d -name .git -prune \) -o -type f ! -name client.sh -print0 | xargs -0 sed -i "s/REPLACE_ME_DISCORD_STAGING_TOKEN/$STAGING_DISCORD_TOKEN/g"
        find . \( -type d -name .git -prune \) -o -type f ! -name client.sh -print0 | xargs -0 sed -i "s/REPLACE_ME_DB_STAGING_NAME/$DB_STAGING_NAME/g"
        find . \( -type d -name .git -prune \) -o -type f ! -name client.sh -print0 | xargs -0 sed -i "s/REPLACE_ME_DB_STAGING_USER/$DB_STAGING_USER/g"
        find . \( -type d -name .git -prune \) -o -type f ! -name client.sh -print0 | xargs -0 sed -i "s/REPLACE_ME_DB_STAGING_USER_PASS/$DB_STAGING_PASS/g"
        find . \( -type d -name .git -prune \) -o -type f ! -name client.sh -print0 | xargs -0 sed -i "s/REPLACE_ME_STAGING_ROOT_PASS/$DB_STAGING_ROOT_PASS/g"
        find . \( -type d -name .git -prune \) -o -type f ! -name client.sh -print0 | xargs -0 sed -i "s/REPLACE_ME_STAGING_DB_PORT/$DB_STAGING_PORT/g"
        rm -f .github/workflows/prod.yml
    else
        rm -f bot_staging.env
        rm -f db_staging.env
        rm -f docker-compose-staging.yml
        rm -f .github/workflows/prod_and_staging.yml
    fi

}

function print_creds () {
    echo "Configured $HOST_OR_IP to be docker-compose ready. Please save these credentials"
    echo "\n-- DB --"
    echo "DB Root Pass is $DB_ROOT_PASS"
    echo "DB Name is $DB_NAME"
    echo "DB User is $DB_USER"
    echo "DB Pass is $DB_PASS"
    echo "\n-- Web Auth --"
    echo "Htpasswd (Web auth) user is $HT_USER"
    echo "Htpasswd (Web auth) password is $HT_PASS"
    echo "\n-- Grafana --"
    echo "Grafana User is $GRAFANA_USER"
    echo "Grafana Pass is $GRAFANA_PASS"
    if $STAGING; then
        echo "\n-- Staging Environment --"
        echo "The prefix that is used for staging env is $STAGING_PREFIX  (for example db user in staging env would be $STAGING_PREFIX_$DB_NAME)"
        echo "Staging DB Root Pass is $DB_STAGING_ROOT_PASS"
        echo "Staging DB Name is $DB_STAGING_NAME"
        echo "Staging DB User is $DB_STAGING_USER"
        echo "Staging DB Pass is $DB_STAGING_PASS"
        echo "Staging DB Port is $DB_STAGING_PORT"
    fi
    echo "\n-- ACTION REQUIRED --"
    echo "If you want a fully functional automated GH Workflow (CICD), add the following secrets to the repo"
    echo "Secret Name: KNOWN_HOSTS\nSecret Value: $KNOWN_HOSTS"
    echo "Secret Name: SSH_KEY\nSecret Value: $docker_compose_host"
    echo "Secret Name: CF_API_KEY\nSecret Value: $CF_API_KEY"
    echo "Secret Name: CF_EMAIL\nSecret Value: $CF_EMAIL"
    echo "Secret Name: DB_DATASOURCE\nSecret Value: $DB_DATASOURCE"
    echo "Secret Name: DBC_STRING\nSecret Value: $DBC_STRING"
    echo "Secret Name: DB_NAME\nSecret Value: $DB_NAME"
    echo "Secret Name: DB_PASS\nSecret Value: $DB_PASS"
    echo "Secret Name: DB_USER\nSecret Value: $DB_USER"
    echo "Secret Name: DISCORD_TOKEN\nSecret Value: $DISCORD_TOKEN"
    echo "Secret Name: GF_SECURITY_ADMIN_PASSWORD\nSecret Value: $GRAFANA_USER"
    echo "Secret Name: GC_SECURITY_ADMIN_PASSWORD\nSecret Value: $GRAFANA_PASS"
    echo "Secret Name: SSH_HOST\nSecret Value: $HOST_OR_IP"
    echo "Secret Name: SSH_USER\nSecret Value: $SSH_USER"
    if $STAGING; then
        echo "Secret Name: STAGING_DISCORD_TOKEN\nSecret Value: $STAGING_DISCORD_TOKEN"
        echo "Secret Name: DB_STAGING_PORT\nSecret Value: $DB_STAGING_PORT"
    fi
}

echo "Getting user input"
get_input
echo "Configuring SSH and creating new keys"
ssh_key_and_config
echo "Running server side scripts"
install_config_packages
echo "Configuring local compose and env files"
configure_local
echo "Outputting credentials"
print_creds