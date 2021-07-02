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

# tests overhead correction
overhead=0

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
    exec
    rm query.sql
    rm results
}

function exec {
    psql -q -h localhost -d $db -c '\timing' -f query.sql > results
}

function cleanup {
    query "DROP TABLE IF EXISTS demo;"
}

# Usage: stats (100 200)
function stats {
    printf '%s\n' "$@" | awk "NR==1  {min=max=\$1}
     NF > 0 {total+=\$1; c++;
             if (\$1<min) {min=\$1}
             if (\$1>max) {max=\$1}
            }
     END {OFMT=\"%.6f\"
          print \"n   : \" c
          print \"min : \" min-$overhead \"ms\"
          print \"max : \" max-$overhead \"ms\"
          print \"avg : \" total/c-$overhead \"ms\"}
    "
    last_avg=$(printf '%s\n' "$@" | awk 'NR==1  {min=max=$1}
     NF > 0 {total+=$1; c++;
             if ($1<min) {min=$1}
             if ($1>max) {max=$1}
            }
     END {OFMT="%.6f"
          print total/c}
    ')
}

# Usage: measure iterations function
function measure {
    runtimes=()
    echo "$1" > query.sql
    for i in $(seq 1 $iterations)
    do
        ts=$(date +%s%N)
        exec
        elapsed=$((($(date +%s%N) - $ts)/1000000))
        runtimes+=($elapsed)
    done
    rm results
    stats "${runtimes[@]}"
}

# ==============================================================================
# INIT
# ==============================================================================
cleanup
echo "Using database $db"
echo "Measuring overhead of calling psql"
measure "SELECT 1;"
overhead=$last_avg
echo "Will subtract $overhead from test results"
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
sql_date_strings=$(printf ",('%s')" "${datevalues[@]}")
sql_date_strings=${sql_date_strings:1}
sql_int_to_date=$(printf ",(to_date(%s::text, 'YYYYMMDD'))" "${intvalues[@]}")
sql_int_to_date=${sql_int_to_date:1}
sql_intval_to_date=$(printf ",(to_date('%s', 'YYYYMMDD'))" "${intvalues[@]}")
sql_intval_to_date=${sql_intval_to_date:1}
sql_ints=$(printf ",(%s)" "${intvalues[@]}")
sql_ints=${sql_ints:1}
sql_date_string_to_int=$(printf ",(to_char('%s'::date, 'YYYYMMDD')::int)" "${datevalues[@]}")
sql_date_string_to_int=${sql_date_string_to_int:1}
echo "done"
echo "Running tests on ${#datevalues[@]} records"
echo "Running each test $iterations times"

echo "========================================================================="
echo "DATE field"
echo "========================================================================="
query "CREATE TABLE demo (date DATE);"
echo "INSERT INTO demo VALUES ('2010-01-01')"
measure "TRUNCATE TABLE demo; INSERT INTO demo (date) VALUES $sql_date_strings;"
echo "-------------------------------------------------------------------------"
echo "INSERT INTO demo VALUES (to_date(20100101::text, 'YYYYMMDD'))"
measure "TRUNCATE TABLE demo; INSERT INTO demo (date) VALUES $sql_int_to_date;"
echo "-------------------------------------------------------------------------"
echo "INSERT INTO demo VALUES (to_date('20100101', 'YYYYMMDD'))"
measure "TRUNCATE TABLE demo; INSERT INTO demo (date) VALUES $sql_intval_to_date;"
echo "-------------------------------------------------------------------------"
echo "SELECT date FROM demo"
measure "SELECT date FROM demo;"
echo "-------------------------------------------------------------------------"
echo "SELECT to_char(date, 'YYYYMMDD')::int FROM demo"
measure "SELECT to_char(date, 'YYYYMMDD')::int FROM demo;"
cleanup

echo "========================================================================="
echo "INTEGER field"
echo "========================================================================="
query "CREATE TABLE demo (date INTEGER);"
echo "INSERT INTO demo VALUES (20100101)"
measure "TRUNCATE TABLE demo; INSERT INTO demo (date) VALUES $sql_ints;"
echo "-------------------------------------------------------------------------"
echo "INSERT INTO demo VALUES (to_char('2010-01-01'::date, 'YYYYMMDD')::int)"
measure "TRUNCATE TABLE demo; INSERT INTO demo (date) VALUES $sql_date_string_to_int;"
echo "-------------------------------------------------------------------------"
echo "SELECT date FROM demo"
measure "SELECT date FROM demo;"
echo "-------------------------------------------------------------------------"
echo "SELECT to_date(date::text, 'YYYYMMDD') FROM demo"
measure "SELECT to_date(date::text, 'YYYYMMDD') FROM demo;"
cleanup
