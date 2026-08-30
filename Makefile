COMPOSE		= docker compose -p inception -f ./srcs/docker-compose.yml
DATA_DIR	= $(HOME)/data

all: up

build:
	$(COMPOSE) build

up:
	mkdir -p $(DATA_DIR)/wordpress $(DATA_DIR)/mariadb
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

clean:
	$(COMPOSE) down -v

fclean: clean
	sudo rm -rf $(DATA_DIR)/wordpress $(DATA_DIR)/mariadb

re: fclean all

.PHONY: all build up down clean fclean re
