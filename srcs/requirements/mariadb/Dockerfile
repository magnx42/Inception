FROM debian:bookworm
RUN apt update -y && apt upgrade -y
RUN apt install mariadb-server -y
COPY conf/mariadb.conf /etc/mysql/mariadb.conf.d/50-server.cnf
COPY conf/script.sh /tmp/script.sh
RUN chmod +x /tmp/script.sh
ENTRYPOINT [ "/tmp/script.sh" ]
CMD ["mariadbd", "--user=mysql"]