*This project has been created as part of the 42 curriculum by mageneix.*

# Inception

## Description

A small web infrastructure built from scratch with Docker Compose: three services, three
containers, three hand-written Dockerfiles, one private network, one encrypted entry point.

| Service     | Role                                  | Base image        | Exposure              |
| ----------- | ------------------------------------- | ----------------- | --------------------- |
| `nginx`     | TLS termination, reverse proxy to PHP | `debian:bookworm` | `443` published       |
| `wordpress` | WordPress 7.0.4 + PHP-FPM 8.2         | `debian:bookworm` | `9000`, internal only |
| `mariadb`   | MariaDB 10.11                         | `debian:bookworm` | `3306`, internal only |

```
client --443--> [ nginx ] --fastcgi:9000--> [ wordpress ] --:3306--> [ mariadb ]
                     \___ shared volume ___/                              |
              /home/mageneix/data/wordpress          /home/mageneix/data/mariadb
```

Site: **https://mageneix.42.fr**, TLSv1.2/1.3 only. Ports 80 and 3306 are unreachable from
the host — NGINX is the only way in.

### Docker and included sources

No ready-made application image is pulled; only `debian:bookworm`, which the subject
allows. NGINX, PHP-FPM, MariaDB and WordPress are installed and configured by the
project's own Dockerfiles. The repository holds the `Makefile`, `srcs/docker-compose.yml`,
and per-service `Dockerfile` + `conf/` (server configs and entrypoint scripts). Two
artefacts are fetched at build time from upstream, not from a registry: the WordPress
tarball from `fr.wordpress.org` and the WP-CLI phar from `wp-cli/builds`.

### Main design choices

- **One process per container, and it is PID 1.** Every entrypoint ends with `exec`, so
  the service replaces the shell: it receives `SIGTERM` directly, and its crash is the
  container's crash, which is what makes the restart policy work. No `tail -f`, no daemon.
- **Idempotent entrypoints.** MariaDB bootstraps only if its data directory is empty;
  WordPress checks `wp core is-installed` before installing. Restarting never reinstalls.
- **Bounded wait, not a blind sleep.** `depends_on` gives start order, not readiness, so
  WordPress polls MariaDB with a real query (30 tries, 1 s apart) and fails loudly.
- **Pinned base, no `latest`.** All images `FROM debian:bookworm`, tagged `<service>:1.0`.

### Virtual Machines vs Docker

A VM emulates hardware and runs its own kernel on a hypervisor. A container shares the
host kernel and is isolated by namespaces (what it sees) and cgroups (what it consumes).
Three VMs here would mean three kernels and three init systems for three processes that
matter; the containers weigh a few hundred MB and start in seconds. The trade-off is the
isolation boundary: a VM is separated by the hypervisor, a container by the kernel it
shares. This is also why a container is not a small VM — no init, one foreground process —
which is exactly what the `tail -f` anti-pattern gets wrong.

### Secrets vs Environment Variables

An environment variable is readable through `docker inspect`, printed by `docker compose
config`, visible in `/proc/<pid>/environ`, and inherited by every child process — here,
PHP-FPM workers, so any WordPress plugin can `getenv()` the database root password. A
Docker secret is mounted as a file in a tmpfs under `/run/secrets`, never enters the image
layers, and is only visible to code that opens it.

This project uses `.env`, which the subject makes mandatory. `.gitignore` excludes it and a
committed `.env.example` documents the keys with placeholders. That prevents leaking
credentials *to the repository* — the failure the subject punishes — but not reading them
*on the machine*. Docker secrets are the stronger answer to that second problem.

### Docker Network vs Host Network

With `network_mode: host` a container shares the host's network namespace: no address of
its own, every listening port is a host port, and two containers wanting the same port
collide. Here it would publish MariaDB on 3306 and PHP-FPM on 9000 to the whole host —
the opposite of "NGINX is the only entry point", which is why the subject forbids it.

The user-defined bridge `inception` gives each container its own namespace on a private
subnet plus Docker's embedded DNS, so `wordpress` resolves `mariadb` by name — no
hardcoded IP, no legacy `--link`. Only published ports cross the boundary, and that is one
line: `443:443`.

### Docker Volumes vs Bind Mounts

A bind mount maps a host path straight in: convenient, but tied to the host layout, with
the host's ownership, and unmanaged — `docker volume ls` ignores it and nothing is
pre-populated. A named volume is a Docker object: listed, removable with `down -v`, and —
the behaviour this project depends on — an empty named volume is populated with the
image's content at that path on first mount. That is why the WordPress files extracted at
build time end up in the volume instead of being masked by it.

This project uses **named volumes** under the top-level `volumes:` key. The subject also
requires the data to live in `/home/login/data`, so each one uses the `local` driver with
`driver_opts` (`type: none`, `o: bind`, `device: /home/mageneix/data/...`): a volume mount
as far as Compose is concerned, with its storage pinned to the required directory. No
service declares a raw `host_path:container_path` bind.

## Instructions

**Prerequisites** — Docker Engine, the Docker Compose v2 plugin, GNU Make, `sudo` (for
`make fclean` only), and the domain resolving locally:

```bash
echo "127.0.0.1    mageneix.42.fr" | sudo tee -a /etc/hosts
```

**Configure** — `srcs/.env` is not in the repository; create it from the template. It is
gitignored and must never be committed. `SITE_ADMIN_NAME` must not contain `admin`.

```bash
cp srcs/.env.example srcs/.env && $EDITOR srcs/.env
```

**Run** — then open https://mageneix.42.fr (self-signed certificate: accept the warning
once). Admin panel at `/wp-admin`.

```bash
make
```

| Target | Effect | Data |
| ------ | ------ | ---- |
| `make` / `make up` | build the images and start the stack | kept |
| `make build` | build only | kept |
| `make down` | stop and remove the containers | **kept** |
| `make clean` | `down` + remove the volumes | destroyed |
| `make fclean` | `clean` + delete `~/data/*` | destroyed |
| `make re` | `fclean` then rebuild | destroyed |

## Resources

- Docker docs, [Compose file reference](https://docs.docker.com/reference/compose-file/),
  [Dockerfile best practices](https://docs.docker.com/build/building/best-practices/),
  [networking](https://docs.docker.com/engine/network/),
  [volumes](https://docs.docker.com/engine/storage/volumes/),
  [secrets](https://docs.docker.com/compose/how-tos/use-secrets/),
  [restart policies](https://docs.docker.com/engine/containers/start-containers-automatically/)
- [Docker and the PID 1 zombie reaping problem](https://blog.phusion.nl/2015/01/20/docker-and-the-pid-1-zombie-reaping-problem/)
- [NGINX](https://nginx.org/en/docs/) · [PHP-FPM](https://www.php.net/manual/en/install.fpm.configuration.php)
  · [MariaDB](https://mariadb.com/kb/en/documentation/) · [WP-CLI](https://developer.wordpress.org/cli/commands/)
  · [openssl req](https://docs.openssl.org/master/man1/openssl-req/)

**Use of AI** — Claude was used as a code reviewer and to help understand Docker and how it works, not as a code generator.