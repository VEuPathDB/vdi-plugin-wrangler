IMAGE_NAME := $(shell grep 'name:' Jenkinsfile | sed "s/.\+'\(.\+\)'.\+/\1/g")

.PHONY: default build test start stop shell logs check-running

default:
	@echo "Usage:"
	@echo "  make build"
	@echo
	@echo "    Builds the docker image for local use."
	@echo
	@echo "  make test"
	@echo
	@echo "    Runs the test suite in a new container (no running container needed)."
	@echo
	@echo "  make shell"
	@echo
	@echo "    Opens a bash session in a running instance of this project's docker image."
	@echo

build:
	@docker compose build

test:
	@docker compose run --rm -w /opt/veupathdb plugin bin/run_tests.R

shell:
	@docker compose run --rm plugin bash
