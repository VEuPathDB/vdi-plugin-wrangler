IMAGE_NAME := $(shell grep 'name:' Jenkinsfile | sed "s/.\+'\(.\+\)'.\+/\1/g")
CONTAINER_CMD := $(shell if command -v podman 2>&1 >/dev/null; then echo podman; else echo $(CONTAINER_CMD); fi)

default:
	@echo "Usage:"
	@echo "  make build"
	@echo
	@echo "    Builds the $(CONTAINER_CMD) image for local use."
	@echo
	@echo "  make start"
	@echo
	@echo "    Starts the project's $(CONTAINER_CMD) image as a background container."
	@echo
	@echo "  make stop"
	@echo
	@echo "    Shuts down a running background container for this project."
	@echo
	@echo "  make shell"
	@echo
	@echo "    Opens a bash session in a running instance of this project's $(CONTAINER_CMD) image."

build:
	@$(CONTAINER_CMD) compose build

start:
	@$(CONTAINER_CMD) compose up -d

stop:
	@$(CONTAINER_CMD) compose down -v

shell:
	@$(CONTAINER_CMD) exec -it $(IMAGE_NAME)-plugin-1 bash

logs:
	@$(CONTAINER_CMD) logs -f $(IMAGE_NAME)-plugin-1
