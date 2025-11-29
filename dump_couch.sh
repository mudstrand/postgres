#!/bin/zsh

pg_dump -h localhost -p 5432 -U postgres -d couch -Fc -f $1