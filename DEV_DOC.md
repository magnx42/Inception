# Developer documentation

How the project is built and how to work on it. For operating an installed stack, see
`USER_DOC.md`.

## Setup from scratch

**Prerequisites** — Docker Engine (tested with 29.7), the Docker Compose **v2** plugin
(`docker compose`, not `docker-compose`), GNU Make, a user in the `docker` group, and
`sudo` for `make fclean` only. The whole project is meant to run inside a VM.

**Layout** — each service's build context is its own directory, so a Dockerfile can only
`COPY` from its `conf/`.

```
Makefile  README.md  USER_DOC.md  DEV_DOC.md  .gitignore
srcs/docker-compose.yml
srcs/.env                 not committed        srcs/.env.example    committed, placeholders
srcs/requirements/mariadb/{Dockerfile, conf/{mariadb.conf, script.sh}}
srcs/requirements/nginx/{Dockerfile, conf/nginx.conf}
srcs/requirements/wordpress/{Dockerfile, conf/{php.conf, auto-config.sh}}
```

**Configuration** — `srcs/.env` is injected into all three containers via `env_file:`.

```bash
cp srcs/.env.example srcs/.env && $EDITOR srcs/.env
echo "127.0.0.1    mageneix.42.fr" | sudo tee -a /etc/hosts
```

Three constraints: `SITE_ADMIN_NAME` must not contain `admin`; `SITE_DOMAIN` must match
`server_name` in `nginx.conf` **and** the certificate `CN` in the NGINX Dockerfile, so
changing the domain means editing both and rebuilding; the `SQL_*` variables are only
applied when the database is first created, and are ignored on an existing volume.

**Secrets** — credentials live in `srcs/.env`, excluded by `.gitignore`. The `.gitignore`
must exist *before* the first `git add`: once a credential is committed, deleting it later
does not remove it from the history. Verify before committing:

```bash
git status --porcelain --untracked-files=all | grep env   # only  ?? srcs/.env.example
```

Migrating to Docker secrets means: non-sensitive keys stay in `.env`, each password goes
into its own file under `secrets/`, declared under the top-level `secrets:` key plus a
per-service list, `secrets/` added to `.gitignore`, and entrypoints read
`SQL_PASSWORD=$(cat /run/secrets/db_password)`.

## Build and launch

Everything goes through Compose, configured once at the top of the Makefile:

```make
COMPOSE = docker compose -p inception -f ./srcs/docker-compose.yml
```

`-p inception` is what names the volumes `inception_wordpress` / `inception_mariadb` and
the network `inception_inception`, independently of where the repository sits.

| Target        | Command behind it                                        | Data                 |
| ------------- | -------------------------------------------------------- | -------------------- |
| `make` / `up` | `mkdir -p ~/data/{wordpress,mariadb}` + `up -d --build`   | preserved            |
| `make build`  | `build`                                                  | preserved            |
| `make down`   | `down`                                                   | preserved            |
| `make clean`  | `down -v`                                                | **volumes destroyed** |
| `make fclean` | `clean` + `sudo rm -rf ~/data/wordpress ~/data/mariadb`   | **erased**           |
| `make re`     | `fclean` + `all`                                         | **erased**           |

`up` passes `--build`, so a modified Dockerfile is picked up without a separate step.

**What happens on `make up`.** Three images are built from `debian:bookworm` and tagged
`<service>:1.0` — the explicit `image:` key is what keeps them off `latest`.

- `mariadb` — `script.sh` checks the `SQL_*` variables, prepares `/run/mysqld`, and only
  if `/var/lib/mysql/$SQL_DATABASE` is absent runs `mariadbd --bootstrap` to create the
  database, the app user and the root password. Then `exec "$@"` hands over to `mariadbd`.
- `wordpress` — `auto-config.sh` polls MariaDB with a real `SELECT 1` (30 tries, 1 s
  apart) because `depends_on` gives order, not readiness. If `wp core is-installed` fails
  it writes `wp-config.php`, installs WordPress and creates the second user. It then
  `chown -R www-data:www-data /var/www/wordpress` on every start — so ownership is correct
  even on a pre-existing volume — and `exec`s `php-fpm8.2 -F` on TCP 9000.
- `nginx` — serves the shared volume, TLSv1.2/1.3 only with the self-signed certificate
  generated at build (valid 365 days), forwards `\.php$` to `wordpress:9000`, and runs
  `daemon off;` so the master stays PID 1.

Every entrypoint ends in `exec`: the service is PID 1, gets `SIGTERM` on `docker stop`,
and its crash is the container's crash — which is what makes the restart policies work.

## Managing containers

```bash
docker ps
docker logs -f wordpress
docker exec -it mariadb bash
docker compose -p inception -f srcs/docker-compose.yml up -d --build nginx   # one service
docker exec nginx nginx -t                                                   # validate conf
docker exec wordpress wp user list --allow-root --path=/var/www/wordpress
docker exec mariadb sh -c 'mariadb -u root -p"$SQL_ROOT_PASSWORD" -e "SHOW DATABASES;"'
```

**Checks the project must pass:**

```bash
curl -kI https://mageneix.42.fr                                    # 200
curl -s -m 3 -o /dev/null -w '%{http_code}\n' http://127.0.0.1/    # 000, port 80 closed
curl -k --tlsv1.1 --tls-max 1.1 https://127.0.0.1/                 # must fail
docker image ls --format '{{.Repository}}:{{.Tag}}' | grep -E '^(nginx|wordpress|mariadb):'
```

Restart policies **cannot** be tested with `docker kill`: Docker treats an explicit kill as
a manual stop and will not restart the container. Simulate a real crash instead:

```bash
sudo kill -9 $(docker inspect -f '{{.State.Pid}}' mariadb)
sleep 10 && docker ps          # mariadb must be back up
```

## Volumes and network

```bash
docker volume ls
docker volume inspect inception_wordpress
docker network inspect inception_inception
make down && docker volume rm inception_wordpress inception_mariadb   # by hand
```

Volumes from an earlier project name are not cleaned up automatically — worth checking
`docker volume ls` after any rename.

## Where the data lives

Both are **named volumes** using the `local` driver with storage pinned to the directory
the subject requires (`type: none`, `o: bind`, `device: /home/mageneix/data/...`).

| Volume                | Host path                       | Mounted at           | Contents                  |
| --------------------- | ------------------------------- | -------------------- | ------------------------- |
| `inception_wordpress` | `/home/mageneix/data/wordpress` | `/var/www/wordpress` | core, themes, plugins, uploads, `wp-config.php` |
| `inception_mariadb`   | `/home/mageneix/data/mariadb`   | `/var/lib/mysql`     | the database              |

The WordPress volume is mounted by **both** `nginx` and `wordpress`: NGINX serves the
static files, PHP-FPM executes the PHP. They must point at the same volume.

On first start the volume is empty and Docker copies the image's content at that path into
it — the copy-up behaviour of volume mounts, which a raw bind mount would not give. That
is why the WordPress files extracted at build time end up on the host.

| Action                 | Containers | Volumes | `~/data` |
| ---------------------- | ---------- | ------- | -------- |
| crash / reboot         | restarted  | kept    | kept     |
| `make down`            | removed    | kept    | kept     |
| `make clean`           | removed    | removed | emptied  |
| `make fclean`          | removed    | removed | deleted  |

State lives in the volumes, not the containers, so `make down && make up` returns the same
site: MariaDB skips its bootstrap and WordPress skips its install.

## Working on the project

Configs and entrypoints are `COPY`ed into the images, so any change needs a rebuild
(`up -d --build <service>`). Both entrypoints are meant to be idempotent — test them by
restarting a container twice, not only on a fresh volume. `make re` tests the from-scratch
path, and erases `~/data`.

**Known trade-offs, if you continue:** credentials are in `.env` rather than Docker
secrets; WordPress stores `siteurl` as `http://mageneix.42.fr` while only 443 is served
(it works, because PHP receives `HTTPS=on` over FastCGI, but installing with
`--url="https://$SITE_DOMAIN"` would be more correct); the certificate is self-signed and
reissued on every NGINX rebuild; and `restart:` is `unless-stopped` for MariaDB but
`on-failure` for the other two — both satisfy the requirement, one policy would be clearer.
