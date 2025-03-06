# vdi-plugin-wrangler

This is a VDI plugin that uses the [Study Wrangler](https://github.com/VEuPathDB/study-wrangler) to process user-uploaded files into EDA-loadable assets.

# Set-up

This is TBC but feel free to ask @bobular about .env files etc.

# Live dev

Create a file `docker-compose.override.yml` with the following

```
services:
  plugin:
    volumes:
      - ./bin:/opt/veupathdb/bin
```
so that you can work on scripts in the `bin` directory without rebuilding/restarting the container.

You can add further paths as required.

