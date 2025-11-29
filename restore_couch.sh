#!/bin/zsh

pg_restore -h localhost -p 5432 -U couch -d couch $1