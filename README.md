# vdi-plugin-wrangler

This is a VDI plugin that uses the [Study Wrangler](https://github.com/VEuPathDB/study-wrangler) to process user-uploaded files into EDA-loadable assets.

## Set-up

This is TBC but feel free to ask @bobular about .env files etc.

### `mount` directory

In your .env file you will need something like this (among others):

```
DATASET_INSTALL_ROOT=/datasets
SITE_BUILD=build-99
```
You should create a directory `mount/build-99` before attempting to build the container.


### build

```
# can take 30 minutes!
make build

# start the container (running a VDI server but you may not need to use it)
make start

# get a shell 
make shell

# test import with data from outside the container
cd /opt/veupathdb
import /datasets/build-99/inputs/my-cool-dataset /datasets/build-99/outputs/my-cool-dataset
```

## Live dev

Create a file `docker-compose.override.yml` with the following

```
services:
  plugin:
    volumes:
      - ./bin:/opt/veupathdb/bin
      - ./lib/R:/opt/veupathdb/lib/R
      - ./tests:/opt/veupathdb/tests
```
so that you can work on the code and tests without rebuilding/restarting the container.

You can add further paths as required.

