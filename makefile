IMAGE_NAME := $(shell grep 'name:' Jenkinsfile | sed "s/.\+'\(.\+\)'.\+/\1/g")

default:
	@echo "Usage:"
	@echo "  make build"
	@echo
	@echo "    Builds the docker image for local use."
	@echo
	@echo "  make start"
	@echo
	@echo "    Starts the project's docker image as a background container."
	@echo
	@echo "  make stop"
	@echo
	@echo "    Shuts down a running background container for this project."
	@echo
	@echo "  make shell"
	@echo
	@echo "    Opens a bash session in a running instance of this project's docker image."
	@echo
	@echo "  make logs"
	@echo
	@echo "    Attaches to the log output of a running instance of this project's docker image."

build:
	@docker compose build

start:
	@docker compose up -d

stop:
	@docker compose down -v

shell:
	@docker exec -it $(IMAGE_NAME)-plugin-1 bash

logs:
	@docker logs -f $(IMAGE_NAME)-plugin-1
