#!/usr/bin/env bash

# install bundle gems if not up to date with the Gemfile.lock file
bundle check 2>/dev/null || bundle install --without unicorn

# install node packages
npm list &> /dev/null || npm ci

# install python packages
[ -f ./venv/bin/pip ] || python3 -m venv ./venv
./venv/bin/python3 -m pip install --upgrade pip > /dev/null
./venv/bin/pip install -r requirements-jupyter.txt -r requirements-scanner.txt > /dev/null

# setup the database (checks for db existence first)
until pg_isready -q; do
  echo "waiting for database to start up"
  sleep 5
done

# sets up the database if it doesn't exist
cp .dockerfiles/database.yml.postgresql config/database.yml
bundle exec rails db:prepare

rm -f ./tmp/pids/server.pid

# Then exec the container's main process (what's set as CMD in the Dockerfile or docker-compose.yml).
exec "$@"
