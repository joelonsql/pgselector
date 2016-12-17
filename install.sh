#!/bin/sh
psql -X -f selector.sql
psql -X -f get_unique_name_for_id.sql
