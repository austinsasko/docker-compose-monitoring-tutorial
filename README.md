# Full Stack Tutorial with Docker Compose

## Pre-Requisites
1. A (Cloudflare)[https://clouflare.com] account with at least 1 domain configured
1. A (Discord account)[https://discord.com] with a (Discord token)[https://www.writebots.com/discord-bot-token/#generating_your_token_step-by-step]
1. A Linux server running either CentOS, AlmaLinux, or RockyLinux that allows password based SSH authentication
1. A fork of (Docker compose tutorial)[https://github.com/austinsasko/docker-compose-monitoring-tutorial]

## Instructions
1. Run ./configure.sh and follow the script steps and save the outputted credentials somewhere safe
1. Create the GH secrets that the script asks you to
1. Commit and push the changes that the configure.sh made. See Github automatically create your docker-compose stack
1. If you would rather manually make the stack rather than let Github CICD make it, just run the following: `docker compose -f docker-compose-monitoring.yml up -d`
`docker compose -f docker-compose-staging.yml up -d`
`docker compose -f docker-compose.yml up -d`

Or if you are unable or prefer not to run the script
(Steps are a WIP)
1. Generate an SSH key that docker compose will use to communicate with the server
1. Create a remote context for docker to use so it knows your docker commands run remotely
1. Find all mentions of "REPLACE_ME" in this repo and replace it with your own values
1. Load the SSH public key into the remote server, install docker-ce and node_exporter,

## Description
This repository is intended to imitate a full enterprise stack for any dockerized app (in this case its a Python discord bot).
High level breakdown of the stack:
-  Database Engine (MariaDB)[https://hub.docker.com/_/mariadb]
-  Database schema management tool (Alembic)[./sql_migrations/Dockerfile]
- Python discord bot (backend discord.py and frontend flask)[./python_discord_bot/Dockerfile]
- Reverse proxy for handling traffic between the internet and the intranet container network - (Traefik)[https://hub.docker.com/_/traefik]
- Debug info webpage - (Traefik Whoami)[https://hub.docker.com/r/traefik/whoami]
The production stack has a mirrored staging stack that excludes the Traefik containers. Additionally, there is a monitoring stack with mostly standard monitoring tools:
- (Prometheus)[https://hub.docker.com/r/prom/prometheus] (Metric storage/monitoring)
- (Grafana)[https://hub.docker.com/r/grafana/grafana] (Data visualization)
- (cadvisor)[https://hub.docker.com/r/google/cadvisor] (Full system metric reporting > Prometheus)
- (alertmanager)[https://hub.docker.com/r/prom/alertmanager] (Alerting > Prometheus)
- (Grafana-Loki)[https://hub.docker.com/r/grafana/loki] (Logging > Grafana)
- (promtail)[https://hub.docker.com/r/grafana/promtail] (Log metrics > Grafana Loki)
- (db_exporter)[https://hub.docker.com/r/prom/mysqld-exporter] (Database metric reporting > Prometheus)
- (promcord)[https://hub.docker.com/r/biospheere/promcord] (Discord metric reporting > Prometheus)
- (query_exporter)[https://hub.docker.com/r/adonato/query-exporter] (Specific table data reporting > Prometheus) instances.

All containers are monitored both from a resource (Prometheus/Grafana metrics) and a docker logs perspective (Sent to Grafana-Loki Dashboard)
The detailed breakdown of the stacks consist of three main categories of containers:
1. A production environment consisting of the following services
    * MariaDB
        * What: Production version of the latest version of database engine MariaDB, a fork of MySQL.
        * How:
          - Will execute the SQL in mariadb/initscript.sql on first run and will apply any custom configuration in mariadb/conf.d/
          - Is not accessible to the internet, strictly an intranet container that has no ingress or egress traffic to the world. Only communicates to the internal containers for DB operations.
        * Customizations: Will run on port 3306
    * Sql_migrations
        * What: Production verison of DB Migration software A/lembic.
        * How:
          - Builds a Python 3.10 slim container and installs alembic through pip. Alembic will control the database schema and structure, to allow consistent and reliable DB operations. At no point should the DB schema be changed via CLI or manually, it should all be codified through Alembic. Example migrations are shown in sql_migrations/versions directory
          - Is not accessible to the internet, strictly an intranet container that has no ingress or egress traffic to the world. Only communicates to the database container.
        * Customizations: Ensure Alembic is installed via pip on your local machine then navigate to sql_migrations/ run `alembic revision -m "Change Description"` and you will have a new .py file in sql_migrations/versions/ that you can edit and configure for your schema.
    * Python_discord_bot
        * What: Production version of a Python Discord Bot. This is the container to swap out for your backend application if you do not want to use a Python Discord bot. Comes with a few functionalities pre-developed (doing an action every x seconds, responding to a command, and getting user information).
        * How:
          - Uses Python 3.10 for the codebase, Discord.py for the integration with Discord, SqlAlchemy for the DB ORM mapping
          - Is not accessible to the internet, strictly an intranet container that has no ingress, only egress traffic for Discord bot handling
        * Customizations: Also comes with a models.py file which uses SQLAlchemy for the ORM to the MariaDB instance. You can use any of the SQLAlchemy async operations in the Python code to easily handle communicating with the DB as if it was just an object. e.g. Discord_user.new() makes a row in the DB AND gives you a Python referenced object to use
    * Python_Bot_Frontend
        * What: Production version of a Flask app. This is an internet facing application that displays information from the DB.
        * How:
          - Uses Python 3.10 for the codebase, Flask for the web application, Waitress to serve the web application to consumers.
          - Is accessible via bot.domain.com, the container listens on hostname python_bot_frontend and port 5000 but bot.domain.com traffic is tunneled through traefik so all HTTP/HTTPS to URL goes to container.
          - No authentication required
        * Customizations: Editing python_flask/templetas/index.html can change how users see when the page. Editing the main.py in the same directory can change what data is fetched from the DB that is presented to the users.
    * Traefik
        * What: Production version of a Trafeik reverse proxy container. This is the load balancer / service / middleware for all containers to receive traffic through
        * How:
          - Builds Traefik 2.5 container. Any docker container in the docker compose file that has a label for Traefik and has the respective configurations in the labels section (see any of the compose yml services for examples) will have its web traffic sent through Traefik. Traefik will automatically provision SSL certificiates since we configure Cloudflare and give it access.
          - Is accessible via traefik.domain.com on port 443.
          - No authentication required
          - Has an endpoint for prometheus to scrape data from on port 5008 /metrics URI
        * Customizations: The only customizations related to Traefik is managing container labels. When a service should be routed through Traefik, it should have the following labels, replacing REPLACE_ME_SERVICE_NAME with the name of the container
        ```- traefik.enable=true
        - traefik.http.routers.REPLACE_ME_SERVICE_NAME.rule=Host(`REPLACE_ME_EXAMPLE_SUBDOMAIN`)
        - traefik.http.routers.REPLACE_ME_SERVICE_NAME.entrypoints=websecure
        - traefik.http.routers.REPLACE_ME_SERVICE_NAME.tls.certresolver=dockerssl
        - traefik.http.services.REPLACE_ME_SERVICE_NAME.loadbalancer.server.port=REPLACE_ME_DEST_CONTAINER_PORT`
        ```
    * Whoami
        * What: Production version of the simple server info tool `traefik/whoami`
        * How:
          - Builds the latest traefik/whoami container as container `simple-service`.
          - Is accessible via whoami.domain.com, the container listens on hostname whoami and port 80 but whoami.domain.com traffic is tunneled through traefik so all HTTP/HTTPS to URL goes to container.
          - Requires authentication, htpasswd web auth user and pass from config script
        * Customizations: None
1. A staging environment consisting of the following services (See corresponding production list item for extra details)
    * MariaDB_staging - Staging version of the latest version of database engine MariaDB, a fork of MySQL.
      Will run on port 3307 unless otherwise specified in config script
    * Sql_migrations_staging - Staging verison of DB Migration software Alembic.
    * Python_discord_bot_staging - Staging verison of Python Discord Bot using the STAGING discord bot token.
    * Python_bot_frontend_staging - Staging verison of Python bot frontend. Accessibla via bot-staging.domain.com rather than prod version of bot.domain.com
    * Traefik and whoami do not have a corresponding staging container as there is no need for them.
1. A monitoring environment consisting of the following services
    * MariaDB
        * What: Grafana-Loki software
        * How:
          - Will build the grafana 2.4.1 release of loki to receive logs on port 3100.
          - Is not accessible to the internet, strictly an intranet container that has no ingress or egress traffic to the world. Only receives communications from the host (docker logs) and can receive logs on port 3100 from any other systems or apps
        * Customizations: NA
    * Promtail
        * What: Grafana-Promtail software
        * How:
          - Will build the grafana 2.4.1 release of promtail to send to loki on 3100.
          - Is not accessible to the internet, strictly an intranet container that has no ingress or egress traffic to the world. Only monitors logs and sends them to Loki
        * Customizations: NA
    * Prometheus
        * What: Prometheus Software
        * How:
          - Will build the Dockerfile from prometheus/ which pulls prometheus 2.7.1 and copies the configs (prometheus.yml and alert.rules) in that directory into the container
          - Is accessible to the internet over prometheus.domain.com. The container listens on hostname prometheus and port 9090 but with Traefik all HTTP/HTTPS traffic to that URL goes to prometheus.
          - Requires authentication, using the username/password provided in initial configuration (htpasswd web auth user/pass)
        * Customizations: Edit prometheus.yml to add new sources for metric reporting and alert.rules for more alerting behaviors
   * Db_Exporter
        * What: Prometheus MySQLd exporter
        * How:
          - Will build the prometheus release of mysqld-exporter that will scrape generic database metrics at certain intervals and report to Prometheus
          - Is not accessible to the internet, strictly an intranet container that has no ingress or egress traffic to the world. Only monitors the local DB and reports to Prometheus
        * Customizations: NA
   * Cadvisor
        * What: Google's cAdvisor software
        * How:
          - Will build Google's release of cadvisor that will scrape monitor the host system resources (containers running, system memory, CPU, network, etc.)
          - Is not accessible to the internet, strictly an intranet container that has no ingress or egress traffic to the world. Only monitors the host hardware and reports to Prometheus.
        * Customizations: NA
   * Promcord
        * What: An open source container for monitoring Discord metrics
        * How:
          - Will build biospheere's release of promcord (Java app) that will scrape Discord for metrics (members, messages, VC time, etc.) and report to Prometheus
          - Is not accessible to the internet for ingress, strictly an egress container just like the Discord bot.
        * Customizations: NA
   * Grafana
        * What: Grafana visualization software
        * How:
          - Will build Grafana's latest release of Grafana.
          - Will copy all of the dashboards and providers from grafana/provisioning into the container.
          - Is accessible to the internet on grafana.domain.com, container listens on hostname grafana and port 3000 but traefik forwards http/https traffic to the container. Does not require htpasswd web auth, requires Grafana admin credentials from the config script
        * Customizations: Can create and edit dashboards, datasources, panels, etc.
   * Alertmanager
        * What: Prometheus's alertmanager container
        * How:
          - Will build Prometheus's release of alertmanager that will manage the alerting behavior (where to send alerts to) when prometheus detects a failure in one of the scraped metric tools
          - Is not accessible to the internet, strictly an intranet container that has no ingress traffic, only egress traffic, to the world. Only monitors the host hardware and alerts to specified providers (Slack/Pagerduty/etc).
        * Customizations: Edit alertmanager/config.yml and configure the alert destinations per [AlertManager Docs](https://prometheus.io/docs/alerting/latest/configuration/)
   * Phpmyadmin
        * What: PHPMyAdmin Software
        * How:
          - Will build phpmyadmins's release of phpmyadmin that will allow users to access the DB via a GUI with any authorized credentials
          - Is accessible to the internet on pma.domain.com. Container listens on hostname phpmyadmin and port 80 but traefik forwards all http/https traffic to the container
          - Requires Pre-authentication, using the htpasswd web auth user/pass from the initial config output AND then the username/password of the DB user you want to authenticate with
        * Customizations: NA

## Docker Compose services format (ordering)
  # logging:
  # container_name:
  # image / build:
  # restart:
  # command:
  # volumes:
  # env file:
  # networks:
  # ports:
  # labels:
  # links:
  # depends: