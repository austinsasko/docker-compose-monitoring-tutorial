#!/bin/bash


function usage () { 
    cat << EOF
    usage: $0 -d domain.com -e x@gmail.com -k cf_api_key -t discord_token -s staging_discord_token -h 1.1.1.1

    OPTIONS:
    -h      Show this message
    -d      Specifies the domain registered in Cloudflare.com
    -e      Specifies the email address used in the Cloudflare.com account
    -k      Specifies the Cloudflare.com API Key. Needs at least DNS Read/Write. Create it here https://developers.cloudflare.com/api/tokens/create/ 
    -t      Specifies the Discord token. Follow the instructions here https://www.writebots.com/discord-bot-token/#generating_your_token_step-by-step
    -s      Specifies the Staging Discord token. Can be the same as the normal discord token if you do not want a staging discord server.
    -p      Specifies the host or IP of the docker compose host server
    -z      Specifies the Zone ID of the Cloudflare domain specified with -d https://community.cloudflare.com/t/where-to-find-zone-id/132913
EOF
}

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
        length=$(( ( RANDOM % 8 )  + 12 ))
    else
        length="$1"
    fi
    echo $(tr -dc 'A-Za-z0-9_' </dev/urandom | head -c $length ; echo '')
}

function get_input () {
    while getopts "hd:e:k:t:s:p:z:" opt; do
        case ${opt} in
            d )
                DOMAIN=$OPTARG
                ;;
            e )
                CF_EMAIL=$OPTARG
                ;;
            k )
                CF_API_KEY=$OPTARG
                ;;
            t )
                DISCORD_TOKEN=$OPTARG
                ;;
            s )
                STAGING_DISCORD_TOKEN=$OPTARG
                ;;
            p )
                HOST_OR_IP=$OPTARG
                ;;
            z )
                CF_ZONE_ID=$OPTARG
                ;;
            h )
                usage
                exit 1
                ;;
            * )
                echo "Invalid Option: -$OPTARG" 1>&2
                echo "Usage: -d [Domain.com] -e [Cloudflare Email] -k [Cloudflare API Key]\
                -t [Discord Token] -s [Staging Discord Token] -h 1.1.1.1"
                echo "  e.g. -d domain.com -e x@gmail.com -k cf_api_key -t discord_token -s staging_discord_token -h 1.1.1.1"
                exit 1
                ;;
        esac
    done

    echo "You will now be asked for information to help us configure your system for docker compose. Press enter to use the default value in []."
    read -p 'Do you want a staging env - recommended [y]: ' STAGING
    if [ -z "$DOMAIN" ]; then
        read -p 'Registered domain in Cloudflare: ' DOMAIN
    fi
    if [ -z "$CF_EMAIL" ]; then
        read -p 'Cloudflare Email Address: ' CF_EMAIL
    fi
    if [ -z "$CF_API_KEY" ]; then
        read -p 'Cloudflare API Key (needs DNS access) (https://developers.cloudflare.com/api/tokens/create/): ' CF_API_KEY
    fi
    if [ -z "$CF_ZONE_ID" ]; then
        read -p 'Cloudflare DNS Zone ID (https://community.cloudflare.com/t/where-to-find-zone-id/132913) : ' CF_ZONE_ID
    fi
    if [ -z "$DISCORD_TOKEN" ]; then
        read -p 'Discord Token (https://www.writebots.com/discord-bot-token/#generating_your_token_step-by-step): ' DISCORD_TOKEN
    fi
    STAGING=${STAGING:-y}
    AUTO_CHECK=$(echo "${STAGING:0:1}" | tr '[:upper:]' '[:lower:]')
    if [ "$STAGING" == "y" ]; then
        STAGING=true
    else
        STAGING=false
    fi
    if $STAGING; then
        if [ -z "$STAGING_DISCORD_TOKEN" ]; then
            read -p 'Staging Discord Token (enter same token as prod if you do not have a staging Discord server): ' STAGING_DISCORD_TOKEN
        fi
    fi
    if [ -z "$HOST_OR_IP" ]; then
        read -p 'SSH Host / IP: ' HOST_OR_IP
    fi
    read -p 'SSH Username [root]: ' SSH_USER
    SSH_USER=${SSH_USER:-root}
    read -p 'SSH Port [22]: ' SSH_PORT
    SSH_PORT=${SSH_PORT:-22}
    read -p 'Would you like me to generate all remaining parameters (datatabase name, DB & Grafana username, DB & Grafana pass, and HTPASSWD values)? [y]: ' AUTO
    AUTO=${AUTO:-y}
    AUTO_CHECK=$(echo "${AUTO:0:1}" | tr '[:upper:]' '[:lower:]')
    if [ "$AUTO" == "y" ]; then
        DB_NAME=$(gen_alphanumeric 4)
        DB_NAME="dbn_$DB_NAME"
        DB_USER=$(gen_alphanumeric 7)
        DB_USER="dbu_$DB_USER"
        DB_PASS=$(gen_alphanumeric)
        DB_ROOT_PASS=$(gen_alphanumeric)
        GRAFANA_USER=$(gen_alphanumeric 4)
        GRAFANA_USER="graf_$GRAFANA_USER"
        GRAFANA_PASS=$(gen_alphanumeric)
        HT_USER=$(gen_alphanumeric 4)
        HT_USER="ht_$HT_USER"
        HT_PASS=$(gen_alphanumeric)
        EXPORTER_PASS=$(gen_alphanumeric)
        if $STAGING; then
            STAGING_PREFIX=$(gen_alphanumeric 4)
            STAGING_PREFIX="${STAGING_PREFIX}_"
            DB_STAGING_NAME="${STAGING_PREFIX}${DB_NAME}"
            DB_STAGING_USER="${STAGING_PREFIX}${DB_USER}"
            DB_STAGING_PASS="${STAGING_PREFIX}${DB_PASS}"
            DB_STAGING_ROOT_PASS="${STAGING_PREFIX}${DB_ROOT_PASS}"
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
        read -p 'DB Exporter Pass: ' EXPORTER_PASS
        if $STAGING; then
            read -p 'Staging environment prefix (the string that gets prepended to staging vars): ' STAGING_PREFIX
            read -p 'Staging DB Port: ' DB_STAGING_PORT
        fi
    fi
    DATA_SOURCE_NAME="exporter:${EXPORTER_PASS}@(mariadb:3306)/${DB_NAME}"
    DB_CONNECTION_STRING="mysql://exporter:${EXPORTER_PASS}@mariadb:3306/${DB_NAME}"
    ENC_HTPASS=$(openssl passwd -apr1 $HT_PASS)
}

function ssh_key_and_config () {
    mv ~/.ssh/config ~/.ssh/config.bak 2>/dev/null
    KNOWN_HOSTS=$(ssh-keyscan -H $HOST_OR_IP 2>&1)
    echo "$KNOWN_HOSTS" >> ~/.ssh/known_hosts 
    ssh-keygen -t rsa -b 4096 -C "docker_compose_client_script" -N "" -f ~/.ssh/docker_compose_host
    SSH_KEY=$(cat ~/.ssh/docker_compose_host)
    PUB_KEY=$(cat ~/.ssh/docker_compose_host.pub)
    ssh $HOST_OR_IP -l $SSH_USER -p $SSH_PORT "echo $PUB_KEY >> ~/.ssh/authorized_keys"
    if [ $? -ne 0 ]; then
        echo "Initial SSH attempt unsuccessful. Please read the Pre-reqs section in the README.md file."
        echo "Make sure PasswordAuth is set to yes on the remote server SSH config"
        exit 1
    fi
    echo "Setting SSH to use the generated keys in the future"
    echo "Host docker-compose
        HostName $HOST_OR_IP
        User     $SSH_USER
        IdentityFile       ~/.ssh/docker_compose_host
        
Host $HOST_OR_IP
    User     $SSH_USER
    IdentityFile       ~/.ssh/docker_compose_host" > ~/.ssh/config
    ssh $HOST_OR_IP -l $SSH_USER -p $SSH_PORT "echo '127.0.0.1 host.docker.internal' >> /etc/hosts"
}

function install_config_packages () {
    echo "Installing Docker engine"
    ssh $HOST_OR_IP -l $SSH_USER -p $SSH_PORT "timedatectl set-timezone America/New_York"
    ssh $HOST_OR_IP -l $SSH_USER -p $SSH_PORT "yum install -y yum-utils epel-release"
    ssh $HOST_OR_IP -l $SSH_USER -p $SSH_PORT "yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo"
    ssh $HOST_OR_IP -l $SSH_USER -p $SSH_PORT "yum install docker-ce docker-ce-cli containerd.io wget fail2ban -y"
    echo "Downloading Node Exporter"
    ssh $HOST_OR_IP -l $SSH_USER -p $SSH_PORT "wget https://github.com/prometheus/node_exporter/releases/download/v1.3.1/node_exporter-1.3.1.linux-amd64.tar.gz"
    echo "Extracting Node Exporter"
    ssh $HOST_OR_IP -l $SSH_USER -p $SSH_PORT "tar -xzf node_exporter*"
    echo "Adding user for node_exporter"
    ssh $HOST_OR_IP -l $SSH_USER -p $SSH_PORT "useradd -rs /bin/false node_exporter"
    echo "Moving node exporter to system install location"
    ssh $HOST_OR_IP -l $SSH_USER -p $SSH_PORT "mv -f node*/node_exporter /usr/local/bin"
    echo "Creating service for node exporter"
    ssh $HOST_OR_IP -l $SSH_USER -p $SSH_PORT 'echo "[Unit]
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
    ssh $HOST_OR_IP -l $SSH_USER -p $SSH_PORT "systemctl daemon-reload"
    ssh $HOST_OR_IP -l $SSH_USER -p $SSH_PORT "systemctl start node_exporter && systemctl status node_exporter && systemctl enable node_exporter"
    ssh $HOST_OR_IP -l $SSH_USER -p $SSH_PORT "systemctl start docker && systemctl status docker && systemctl enable docker"
    ssh $HOST_OR_IP -l $SSH_USER -p $SSH_PORT "systemctl start fail2ban && systemctl status fail2ban && systemctl enable fail2ban"
    ssh $HOST_OR_IP -l $SSH_USER -p $SSH_PORT "docker plugin install grafana/loki-docker-driver:latest --alias loki --grant-all-permissions"
    ssh $HOST_OR_IP -l $SSH_USER -p $SSH_PORT 'sed -i "s|#MaxSessions 10|MaxSessions 30|g" /etc/ssh/sshd_config'
    ssh $HOST_OR_IP -l $SSH_USER -p $SSH_PORT "systemctl restart sshd"
}

function configure_local () {
    cd custom/
    rm -f bot_staging.env bot.env db_staging.env db.env mon.env traefik.env ../traefik/.htpasswd ../query_exporter/query_exporter_config.yaml ../mariadb/initscripts/user.sql ../mariadb/initscripts/table.sql
    for file in *.example; do
        cp -- "$file" "${file%%.example}"
    done
    mv *.sql ../mariadb/initscripts/
    mv traefik.htpasswd ../traefik/traefik.htpasswd
    mv query_exporter_config.yaml ../query_exporter/
    docker context rm docker_compose_tut -f 2>/dev/null
    docker context create docker_compose_tut --docker "host=ssh://$SSH_USER@$HOST_OR_IP:$SSH_PORT"
    docker context use docker_compose_tut
    find . \( -type d -name .git -prune \) -o -type f ! -name configure.sh ! -name "*.example" -print0 | xargs -0 sed -i "s|REPLACE_ME_DISCORD_TOKEN|$DISCORD_TOKEN|g"
    find . \( -type d -name .git -prune \) -o -type f ! -name configure.sh ! -name "*.example" -print0 | xargs -0 sed -i "s|REPLACE_ME_DB_NAME|$DB_NAME|g"
    find . \( -type d -name .git -prune \) -o -type f ! -name configure.sh ! -name "*.example" -print0 | xargs -0 sed -i "s|REPLACE_ME_DB_USER_PASS|$DB_PASS|g"
    find . \( -type d -name .git -prune \) -o -type f ! -name configure.sh ! -name "*.example" -print0 | xargs -0 sed -i "s|REPLACE_ME_DB_USER|$DB_USER|g"
    find . \( -type d -name .git -prune \) -o -type f ! -name configure.sh ! -name "*.example" -print0 | xargs -0 sed -i "s|REPLACE_ME_DB_ROOT_PASS|$DB_ROOT_PASS|g"
    find . \( -type d -name .git -prune \) -o -type f ! -name configure.sh ! -name "*.example" -print0 | xargs -0 sed -i "s|REPLACE_ME_DOMAIN|$DOMAIN|g"
    find . \( -type d -name .git -prune \) -o -type f ! -name configure.sh ! -name "*.example" -print0 | xargs -0 sed -i "s|REPLACE_ME_CF_EMAIL|$CF_EMAIL|g"
    find . \( -type d -name .git -prune \) -o -type f ! -name configure.sh ! -name "*.example" -print0 | xargs -0 sed -i "s|REPLACE_ME_CF_DNS_API_TOKEN|$CF_API_KEY|g"
    find . \( -type d -name .git -prune \) -o -type f ! -name configure.sh ! -name "*.example" -print0 | xargs -0 sed -i "s|REPLACE_ME_ZONE_ID|$CF_ZONE_ID|g"
    find . \( -type d -name .git -prune \) -o -type f ! -name configure.sh ! -name "*.example" -print0 | xargs -0 sed -i "s|REPLACE_ME_WEB_AUTH_USER|$HT_USER|g"
    find . \( -type d -name .git -prune \) -o -type f ! -name configure.sh ! -name "*.example" -print0 | xargs -0 sed -i "s|REPLACE_ME_WEB_AUTH_BCRYPT_PASSWORD|$ENC_HTPASS|g"
    find . \( -type d -name .git -prune \) -o -type f ! -name configure.sh ! -name "*.example" -print0 | xargs -0 sed -i "s|REPLACE_ME_GRAFANA_USER|$GRAFANA_USER|g"
    find . \( -type d -name .git -prune \) -o -type f ! -name configure.sh ! -name "*.example" -print0 | xargs -0 sed -i "s|REPLACE_ME_GRAFANA_PASS|$GRAFANA_PASS|g"
    find . \( -type d -name .git -prune \) -o -type f ! -name configure.sh ! -name "*.example" -print0 | xargs -0 sed -i "s|REPLACE_ME_DATASOURCE_NAME|$DATA_SOURCE_NAME|g"
    find . \( -type d -name .git -prune \) -o -type f ! -name configure.sh ! -name "*.example" -print0 | xargs -0 sed -i "s|REPLACE_ME_DBC_STRING|$DB_CONNECTION_STRING|g"
    find . \( -type d -name .git -prune \) -o -type f ! -name configure.sh ! -name "*.example" -print0 | xargs -0 sed -i "s|REPLACE_ME_EXPORTER_PASS|$EXPORTER_PASS|g"
    if $STAGING; then
        find . \( -type d -name .git -prune \) -o -type f ! -name configure.sh ! -name "*.example" -print0 | xargs -0 sed -i "s|REPLACE_ME_DISCORD_STAGING_TOKEN|$STAGING_DISCORD_TOKEN|g"
        find . \( -type d -name .git -prune \) -o -type f ! -name configure.sh ! -name "*.example" -print0 | xargs -0 sed -i "s|REPLACE_ME_DB_STAGING_NAME|$DB_STAGING_NAME|g"
        find . \( -type d -name .git -prune \) -o -type f ! -name configure.sh ! -name "*.example" -print0 | xargs -0 sed -i "s|REPLACE_ME_DB_STAGING_USER_PASS|$DB_STAGING_PASS|g"
        find . \( -type d -name .git -prune \) -o -type f ! -name configure.sh ! -name "*.example" -print0 | xargs -0 sed -i "s|REPLACE_ME_DB_STAGING_USER|$DB_STAGING_USER|g"
        find . \( -type d -name .git -prune \) -o -type f ! -name configure.sh ! -name "*.example" -print0 | xargs -0 sed -i "s|REPLACE_ME_DB_STAGING_ROOT_PASS|$DB_STAGING_ROOT_PASS|g"
        find . \( -type d -name .git -prune \) -o -type f ! -name configure.sh ! -name "*.example" -print0 | xargs -0 sed -i "s|REPLACE_ME_DB_STAGING_PORT|$DB_STAGING_PORT|g"
        rm -f ../.github/workflows/prod.yml
    else
        rm -f bot_staging.env
        rm -f db_staging.env
        rm -f ../docker-compose-staging.yml
        rm -f ../.github/workflows/prod_and_staging.yml
    fi
    cd ../
}

function print_creds () {
    echo "Configured $HOST_OR_IP to be docker-compose ready. Please save these credentials"
    echo -e "\n-- DB --"
    echo "DB Root Pass is $DB_ROOT_PASS"
    echo "DB Name is $DB_NAME"
    echo "DB User is $DB_USER"
    echo "DB Pass is $DB_PASS"
    echo -e "\n-- Web Auth --"
    echo "Htpasswd (Web auth) user is $HT_USER"
    echo "Htpasswd (Web auth) password is $HT_PASS"
    echo -e "\n-- Grafana --"
    echo "Grafana User is $GRAFANA_USER"
    echo "Grafana Pass is $GRAFANA_PASS"
    if $STAGING; then
        echo -e "\n-- Staging Environment --"
        echo "The prefix that is used for staging env is $STAGING_PREFIX  (for example db user in staging env would be ${STAGING_PREFIX}${DB_NAME})"
        echo "Staging DB Root Pass is $DB_STAGING_ROOT_PASS"
        echo "Staging DB Name is $DB_STAGING_NAME"
        echo "Staging DB User is $DB_STAGING_USER"
        echo "Staging DB Pass is $DB_STAGING_PASS"
        echo "Staging DB Port is $DB_STAGING_PORT"
    fi
    echo -e "\n-- ACTION REQUIRED --"
    echo "If you want a fully functional automated GH Workflow (CICD), add the following secrets to the repo"
    echo -e "Secret Name: KNOWN_HOSTS\nSecret Value: \n$KNOWN_HOSTS"
    echo -e "Secret Name: SSH_KEY\nSecret Value: \n$SSH_KEY"
    echo -e "Secret Name: SSH_HOST\nSecret Value: $HOST_OR_IP"
    echo -e "Secret Name: SSH_USER\nSecret Value: $SSH_USER"
    echo -e "Secret Name: SSH_PORT\nSecret Value: $SSH_PORT"

    echo -e "Secret Name: CF_DOMAIN\nSecret Value: $DOMAIN"
    echo -e "Secret Name: CF_ZONE_ID\nSecret Value: $CF_ZONE_ID"
    echo -e "Secret Name: CF_API_KEY\nSecret Value: $CF_API_KEY"
    echo -e "Secret Name: CF_EMAIL\nSecret Value: $CF_EMAIL"

    echo -e "Secret Name: DB_NAME\nSecret Value: $DB_NAME"
    echo -e "Secret Name: DB_PASS\nSecret Value: $DB_PASS"
    echo -e "Secret Name: DB_USER\nSecret Value: $DB_USER"
    echo -e "Secret Name: DB_DATASOURCE\nSecret Value: $DATA_SOURCE_NAME"
    echo -e "Secret Name: DBC_STRING\nSecret Value: $DB_CONNECTION_STRING"
    echo -e "Secret Name: EXPORTER_PASS\nSecret Value: $EXPORTER_PASS"

    echo -e "Secret Name: DISCORD_TOKEN\nSecret Value: $DISCORD_TOKEN"

    echo -e "Secret Name: GF_ADMIN_USER\nSecret Value: $GRAFANA_USER"
    echo -e "Secret Name: GF_ADMIN_PASS\nSecret Value: $GRAFANA_PASS"

    echo -e "Secret Name: T_HTUSER\nSecret Value: $HT_USER"
    echo -e "Secret Name: T_HTPASSWD\nSecret Value: $ENC_HTPASS"

    if $STAGING; then
        echo -e "Secret Name: STAGING_DISCORD_TOKEN\nSecret Value: $STAGING_DISCORD_TOKEN"
        echo -e "Secret Name: DB_STAGING_NAME\nSecret Value: $DB_STAGING_NAME"
        echo -e "Secret Name: DB_STAGING_USER_PASS\nSecret Value: $DB_STAGING_PASS"
        echo -e "Secret Name: DB_STAGING_USER\nSecret Value: $DB_STAGING_USER"
        echo -e "Secret Name: DB_STAGING_PORT\nSecret Value: $DB_STAGING_PORT"
    fi
}

# Getting user input
get_input "$@"
echo "Configuring SSH hosts, keys, and fingerprints. Then will prompt you for the root password"
ssh_key_and_config
echo "Running server side scripts"
install_config_packages
echo "Configuring local compose and env files"
configure_local
echo "Outputting credentials"
print_creds