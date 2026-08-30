FROM debian:bookworm
RUN apt update
RUN apt install nginx vim curl openssl -y

# dossier permettant de stocker le certificat et la clef
RUN mkdir -p /etc/nginx/ssl /var/run/nginx
RUN openssl req -x509 -nodes -days 365 -out /etc/nginx/ssl/inception.crt -keyout /etc/nginx/ssl/inception.key -subj "/C=FR/ST=IDF/L=Paris/O=42/CN=mageneix.42.fr/UID=mageneix"
COPY conf/nginx.conf /etc/nginx/nginx.conf
RUN chmod 755 /var/www/html
RUN chown -R www-data:www-data /var/www/html
#-g donne une instruction sans [asser par le .conf et le daemon sert a ne pas le faire passer en mode daemon (arriere plan)
CMD ["nginx", "-g", "daemon off;"]

