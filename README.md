# Docker Compose Installation

### Database
- Create a postgres user witht he correct permissions.
- Create the schema in the Postgres database and check the permissions.

### Dokploy
- Create a Dokploy Compose Service and link it to the Github repo and the correct branch.
- Point to ./docker-compose-dokploy.yml
- Fill out all the environment variables.

####  Environment Variables

```dotenv
NODEBB_URL=YOUR_SITE_PUBLIC_URL
NODEBB_SECRET=RANDOM_STRING
NODEBB_DATABASE=DATABASE_TYPE
NODEBB_PORT=EXPOSED_PORT
# Necessary to build the NodeBB server
START_BUILD=true

# Postgres Config
NODEBB_POSTGRES_HOST=HOST
NODEBB_POSTGRES_PORT=PORT
NODEBB_POSTGRES_USERNAME=DB_USERNAME
NODEBB_POSTGRES_PASSWORD=DB_PASSWORD
NODEBB_POSTGRES_DATABASE=DB_NAME
NODEBB_POSTGRES_SCHEMA=DB_SCHEMA
NODEBB_POSTGRES_SSL=ENABLE_SSL_CHECK
NODEBB_POSTGRES_SSL_REJECT_UNAUTHORIZED=ENABLE_SSL_REJECT_UNAUTHORIZED

# Default admin user
NODEBB_ADMIN_USERNAME: ADMIN_USERNAME
NODEBB_ADMIN_PASSWORD: ADMIN_PASSWORD
NODEBB_ADMIN_EMAIL: ADMIN_EMAIL
```

### NodeBB Setup
With this setup NodeBB does not launch the setup wizard on it's own, so we need to do it in the container the first time to initialize the database.

> [!WARNING]
> Only do this once on a fresh install when the database is fresh.

Enter the docker container terminal:
```bash
docker exec -it <container-name> sh
````

Run the setup wizard:
```bash
node ./nodebb setup --config=/opt/config/config.json
```

Restart the container (can be done in Dokploy as well):
```bash
docker restart <container-name>
```
