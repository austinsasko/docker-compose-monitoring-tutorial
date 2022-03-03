# Full Stack Tutorial with Docker Compose

## Description
This repository is intended to imitate a full enterprise stack for any dockerized app (in this case its a Python discord bot). The stack consists of three main components: 
1. A production environment consisting of the following services
    * MariaDB
        * What: Production version of the latest version of database engine MariaDB, a fork of MySQL.
        * How: Will execute the SQL in mariadb/initscript.sql on first run and will apply any custom configuration in mariadb/conf.d/
        * Customizations: Will run on port 3306
    * Sql_migrations
        * What: Production verison of DB Migration software Alembic.
        * How: Builds a Python 3.10 slim container and installs alembic through pip. Alembic will control the database schema and structure, to allow consistent and reliable DB operations. At no point should the DB schema be changed via CLI or manually, it should all be codified through Alembic. Example migrations are shown in sql_migrations/versions directory
        * Customizations: Ensure Alembic is installed via pip on your local machine then navigate to sql_migrations/ run `alembic revision -m "Change Description"` and you will have a new .py file in sql_migrations/versions/ that you can edit and configure for your schema. 
    * Python_discord_bot
        * What: Production version of a Python Discord Bot. This is the container to swap out for your backend application if you do not want to use a Python Discord bot. Comes with a few functionalities pre-developed (doing an action every x seconds, responding to a command, and getting user information). 
        * How: Uses Python 3.10 for the codebase, Discord.py for the integration with Discord, SqlAlchemy for the DB ORM mapping
        * Customizations: Also comes with a models.py file which uses SQLAlchemy for the ORM to the MariaDB instance. You can use any of the SQLAlchemy async operations in the Python code to easily handle communicating with the DB as if it was just an object. e.g. Discord_user.new() makes a row in the DB AND gives you a Python referenced object to use
    * Python_Bot_Frontend
        * What: Production version of a Flask app. This is an internet facing application that displays information from the DB. 
        * How: Uses Python 3.10 for the codebase, Flask for the web application, Waitress to serve the web application to consumers. 
        * Customizations: Editing python_flask/templetas/index.html can change how users see when the page. Editing the main.py in the same directory can change what data is fetched from the DB that is presented to the users.
    * Traefik
        * What: Production version of a Trafeik reverse proxy container. This is the load balancer / service / middleware for all containers to receive traffic through
        * How: Builds Traefik 2.5 container. Any docker container in the docker compose file that has a label for Traefik and has the respective configurations in the labels section (see any of the compose yml services for examples) will have its web traffic sent through Traefik. Traefik will automatically provision SSL certificiates since we configure Cloudflare and give it access.
        * Customizations: The only customizations related to Traefik is managing container labels. When a service should be routed through Traefik, it should have the following labels, replacing REPLACE_ME_SERVICE_NAME with the name of the container
        ```- traefik.enable=true
        - traefik.http.routers.REPLACE_ME_SERVICE_NAME.rule=Host(`REPLACE_ME_EXAMPLE_SUBDOMAIN`)
        - traefik.http.routers.REPLACE_ME_SERVICE_NAME.entrypoints=websecure
        - traefik.http.routers.REPLACE_ME_SERVICE_NAME.tls.certresolver=dockerssl
        - traefik.http.services.REPLACE_ME_SERVICE_NAME.loadbalancer.server.port=REPLACE_ME_DEST_CONTAINER_PORT`
        ```
    * Whoami
        * What: 
        * How:
        * Customizations:
1. A staging environment consisting of the following services (See corresponding production list item for extra details)
    * MariaDB - Staging version of the latest version of database engine MariaDB, a fork of MySQL.
      Will run on port 3307 unless otherwise specified in config script
    * Sql_migrations - Staging verison of DB Migration software Alembic.

1. A monitoring environment consisting of the following services 
    *
A repository set up to deploy multiple containers using docker compose as well as to monitor the stack using Prometheus, Grafana, Loki, Node Exporter, DB Exporter, and promtail

The repository 

## Instructions
1.

## Structure/ordering for Docker Compose files
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