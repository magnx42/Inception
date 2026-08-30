# User documentation

For running an already installed stack. To set it up from scratch, see `DEV_DOC.md`.

## Services

| Container   | Role                                                    | Reachable from |
| ----------- | ------------------------------------------------------- | -------------- |
| `nginx`     | serves the site over HTTPS, forwards PHP to WordPress    | your machine, port 443 |
| `wordpress` | runs WordPress through PHP-FPM                           | `nginx` only   |
| `mariadb`   | stores posts, pages, users, settings                     | `wordpress` only |

Only NGINX is reachable from outside; the database is not exposed at all. The site files
and the database live in `/home/mageneix/data/`, outside the containers, so they survive
stopping and rebuilding them.

## Start and stop

Run from the project root, where the `Makefile` is.

```bash
make          # start (first run builds the images: a few minutes)
make down     # stop — the site and the database are NOT touched
```

Containers restart on their own after a crash or a reboot.

**These delete data, with no undo:** `make clean` removes the volumes, `make fclean` also
deletes `~/data/`. The next `make` then gives an empty site. Back up first (see below).

## Access

| What        | Address                             |
| ----------- | ----------------------------------- |
| Website     | https://mageneix.42.fr              |
| Admin panel | https://mageneix.42.fr/wp-admin     |

Two normal surprises: the browser warns about the certificate (it is self-signed — accept
the exception once), and `http://` does not work (port 80 is closed by design). If the
page does not load at all, check the local mapping:

```bash
grep 42.fr /etc/hosts        # expected: 127.0.0.1    mageneix.42.fr
```

The site has two accounts: an administrator (`SITE_ADMIN_NAME`) and an author
(`SITE_USER_NAME`).

## Credentials

All of them are in **`srcs/.env`**, which is not in the Git repository and must never be
added to it. `srcs/.env.example` is committed and must only ever contain placeholders.

| Variable                                                | What it is                     |
| ------------------------------------------------------- | ------------------------------ |
| `SQL_ROOT_PASSWORD`                                      | MariaDB `root` password        |
| `SQL_USER`, `SQL_PASSWORD`, `SQL_DATABASE`               | WordPress's database access    |
| `SITE_ADMIN_NAME`, `SITE_ADMIN_PASS`, `SITE_ADMIN_EMAIL` | WordPress administrator        |
| `SITE_USER_NAME`, `SITE_USER_PASS`, `SITE_USER_EMAIL`    | second account (author)        |
| `SITE_DOMAIN`, `SITE_NAME`, `LOCALE`                     | domain, title, language        |

Change a **WordPress** password from *Users → Profile*, or:

```bash
docker exec wordpress wp user update mageneix_ad --user_pass='new-password' \
  --allow-root --path=/var/www/wordpress
```

then update `srcs/.env` so the file stays truthful. A **database** password cannot be
changed by editing `.env`: those values are only applied when the database is first
created. Changing it for real means changing it in MariaDB *and* in `wp-config.php`.

## Checking that it works

```bash
docker ps                    # three lines: nginx, wordpress, mariadb, all "Up"
curl -kI https://mageneix.42.fr    # HTTP/1.1 200 OK
docker logs mariadb          # or nginx / wordpress, when something is wrong
```

A `200` means all three services are working — a database failure would show a `500`.

| Symptom                                    | Cause                                                        |
| ------------------------------------------ | ------------------------------------------------------------ |
| Page does not load                         | containers down, or the `/etc/hosts` line is missing          |
| "Error establishing a database connection" | MariaDB not up — check `docker logs mariadb`                  |
| Certificate warning / `http://` fails      | both are expected                                             |
| A container keeps restarting               | its entrypoint fails; usually a missing variable in `.env`     |

## Backup

```bash
make down
sudo tar czf ~/inception-backup-$(date +%F).tar.gz -C /home/mageneix data
make
```

Database only:

```bash
docker exec mariadb sh -c 'mariadb-dump -u root -p"$SQL_ROOT_PASSWORD" --all-databases' > dump.sql
```
