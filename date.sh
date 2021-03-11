#!/usr/bin/env bash

# ==============================================================================
# VARS
# ==============================================================================

# If needed, set 
# export PGHOST=localhost
# export PGPORT=5432
# export PGUSER=user
# export PGPASSWORD=password
# export PATH=$PATH:$EXIVITY_PROGRAM_PATH/server/pgsql/bin

db="${PGDATABASE:-test}"

# records
first_date="2020-01-01"
last_date="2020-12-31"
multiply=1000

# iterations
iterations=10

# ==============================================================================
# FUNCTIONS
# ==============================================================================

function join {
    local IFS="$1"
    shift
    "$*"
}

function query {
    echo $1 > query.sql
    psql -q -d $db -f query.sql > results
    rm query.sql
    rm results
}

function cleanup {
    query "DROP TABLE IF EXISTS demo;"
}

# Usage: stats (100 200)
function stats {
    printf '%s\n' "$@" | awk 'NR==1  {min=max=$1}
     NF > 0 {total+=$1; c++;
             if ($1<min) {min=$1}
             if ($1>max) {max=$1}
            }
     END {OFMT="%.6f"
          print "n   : " c
          print "min : " min "ms"
          print "max : " max "ms"
          print "avg : " total/c "ms"}
    '
}

# Usage: measure iterations function
function measure {
    runtimes=()
    n=$1
    shift
    for i in $(seq 1 $n)
    do
        ts=$(date +%s%N)
        "$@"
        elapsed=$((($(date +%s%N) - $ts)/1000000))
        runtimes+=($elapsed)
    done
    stats "${runtimes[@]}"
}

# ==============================================================================
# INIT
# ==============================================================================

cleanup

echo "Using database $db"
echo -n "Generating values... "

date=$first_date
datevalues=()
intvalues=()
while [ "$date" != $last_date ]
do 
    date=$(date -I -d "$date + 1 day")
    for i in $(seq 1 $multiply)
    do
        datevalues+=($date)
        intvalues+=(${date//[-]/})
    done
done
echo "done"

echo "Running tests on ${#datevalues[@]} records"
echo "Running each test $iterations times"

sql_date_strings=$(printf ",('%s')" "${datevalues[@]}")
sql_date_strings=${sql_date_strings:1}

sql_int_to_date=$(printf ",(to_date(%s::text, 'YYYYMMDD'))" "${intvalues[@]}")
sql_int_to_date=${sql_int_to_date:1}

sql_ints=$(printf ",(%s)" "${intvalues[@]}")
sql_ints=${sql_ints:1}

sql_date_string_to_int=$(printf ",(to_char('%s'::date, 'YYYYMMDD')::int)" "${datevalues[@]}")
sql_date_string_to_int=${sql_date_string_to_int:1}

echo "========================================================================="
echo "DATE field"
echo "========================================================================="

query "CREATE TABLE demo (date DATE);"

echo "INSERT INTO demo VALUES ('2010-01-01')"
measure $iterations query "TRUNCATE TABLE demo; INSERT INTO demo (date) VALUES $sql_date_strings;"
echo "========================================================================="
echo "INSERT INTO demo VALUES (to_date(20100101::text, 'YYYYMMDD'))"
measure $iterations query "TRUNCATE TABLE demo; INSERT INTO demo (date) VALUES $sql_int_to_date;"
echo "========================================================================="
echo "SELECT date FROM demo"
measure $iterations query "SELECT date FROM demo;"
echo "========================================================================="
echo "SELECT to_char(date, 'YYYYMMDD')::int FROM demo"
measure $iterations query "SELECT to_char(date, 'YYYYMMDD')::int FROM demo;"

cleanup

echo "========================================================================="
echo "INTEGER field"
echo "========================================================================="

query "CREATE TABLE demo (date INTEGER);"

echo "INSERT INTO demo VALUES (20100101)"
measure $iterations query "TRUNCATE TABLE demo; INSERT INTO demo (date) VALUES $sql_ints;"
echo "========================================================================="
echo "INSERT INTO demo VALUES (to_char('2010-01-01'::date, 'YYYYMMDD')::int)"
measure $iterations query "TRUNCATE TABLE demo; INSERT INTO demo (date) VALUES $sql_date_string_to_int;"
echo "========================================================================="
echo "SELECT date FROM demo"
measure $iterations query "SELECT date FROM demo;"
echo "========================================================================="
echo "SELECT to_date(date::text, 'YYYYMMDD') FROM demo"
measure $iterations query "SELECT to_date(date::text, 'YYYYMMDD') FROM demo;"

cleanup
