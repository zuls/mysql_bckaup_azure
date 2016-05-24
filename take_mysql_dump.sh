#!/bin/bash

if [[ -n "$DB_DUMP_DEBUG" ]]; then
  set -x
fi

# set our defaults
# DB_DUMP_FREQ = how often to run a backup in minutes, i.e. how long to wait from the most recently completed to the next
DB_DUMP_FREQ=${DB_DUMP_FREQ:-1440}
# DB_DUMP_BEGIN = what time to start the first backup upon execution. If starts with '+' it means, "in x minutes"
DB_DUMP_BEGIN=${DB_DUMP_BEGIN:-+0}
# DB_DUMP_TARGET = where to place the backup file. Can be URL (e.g. smb://server/share/path) or just file path /foo
DB_DUMP_TARGET=${DB_DUMP_TARGET:-/backup}
# login credentials
DBUSER=${DB_USER:-cattle}
DBPASS=${DB_PASS:-cattle}
STORAGE_ACCOUNT_NAME=${STORAGE_ACCOUNT_NAME}
STORAGE_CONTAINER=${STORAGE_CONTAINER}
STORAGE_ACCOUNT_KEY=${STORAGE_ACCOUNT_KEY}

# database server
DBSERVER=db

# temporary dump dir
TMPDIR=/tmp/backups
TMPRESTORE=/tmp/restorefile

# this is global, so has to be set outside
declare -A uri



#
# URI parsing function
#
# The function creates global variables with the parsed results.
# It returns 0 if parsing was successful or non-zero otherwise.
#
# [schema://][user[:password]@]host[:port][/path][?[arg1=val1]...][#fragment]
#
function uri_parser() {
  uri=()
  # uri capture
  full="$@"

    # safe escaping
    full="${full//\`/%60}"
    full="${full//\"/%22}"

		# URL that begins with '/' is like 'file:///'
		if [[ "${full:0:1}" == "/" ]]; then
			full="file://localhost${full}"
		fi
		# file:/// should be file://localhost/
		if [[ "${full:0:8}" == "file:///" ]]; then
			full="${full/file:\/\/\//file://localhost/}"
		fi
		
    # top level parsing
    pattern='^(([a-z0-9]{2,5})://)?((([^:\/]+)(:([^@\/]*))?@)?([^:\/?]+)(:([0-9]+))?)(\/[^?]*)?(\?[^#]*)?(#.*)?$'
    [[ "$full" =~ $pattern ]] || return 1;

    # component extraction
    full=${BASH_REMATCH[0]}
		uri[uri]="$full"
    uri[schema]=${BASH_REMATCH[2]}
    uri[address]=${BASH_REMATCH[3]}
    uri[user]=${BASH_REMATCH[5]}
    uri[password]=${BASH_REMATCH[7]}
    uri[host]=${BASH_REMATCH[8]}
    uri[port]=${BASH_REMATCH[10]}
    uri[path]=${BASH_REMATCH[11]}
    uri[query]=${BASH_REMATCH[12]}
    uri[fragment]=${BASH_REMATCH[13]}
		if [[ ${uri[schema]} == "smb" && ${uri[path]} =~ ^/([^/]*)(/?.*)$ ]]; then
			uri[share]=${BASH_REMATCH[1]}
			uri[sharepath]=${BASH_REMATCH[2]}
		fi
		
		# does the user have a domain?
		if [[ -n ${uri[user]} && ${uri[user]} =~ ^([^\;]+)\;(.+)$ ]]; then
			uri[userdomain]=${BASH_REMATCH[1]}
			uri[user]=${BASH_REMATCH[2]}
		fi
		return 0
}



if [[ -n "$DB_RESTORE_TARGET" ]]; then
	uri_parser ${DB_RESTORE_TARGET}
  if [[ "${uri[schema]}" == "file" ]]; then
    cp $DB_RESTORE_TARGET $TMPRESTORE 2>/dev/null
  elif [[ "${uri[schema]}" == "s3" ]]; then
    aws s3 cp $DB_RESTORE_TARGET $TMPRESTORE
	elif [[ "${uri[schema]}" == "smb" ]]; then
		if [[ -n "${uri[user]}" ]]; then
			UPASS="-U ${uri[user]}%${uri[password]}"
		else
			UPASS=
		fi
		if [[ -n "${uri[userdomain]}" ]]; then
			UDOM="-W ${uri[userdomain]}"
		else
			UDOM=
		fi
    smbclient -N //${uri[host]}/${uri[share]} ${UPASS} ${UDOM} -c "get ${uri[sharepath]} ${TMPRESTORE}"
  fi
  # did we get a file?
  if [[ -f "$TMPRESTORE" ]]; then
    gunzip < $TMPRESTORE | mysql -h $DBSERVER -u $DBUSER -p$DBPASS
    /bin/rm -f $TMPRESTORE
    exit 0
  else
    echo "Could not find restore file $DB_RESTORE_TARGET"
    exit 1
  fi
else
	# determine target proto
	uri_parser ${DB_DUMP_TARGET}

  # wait for the next time to start a backup
  # for debugging
  echo Starting at $(date)
  current_time=$(date +"%s")
  # get the begin time on our date
  # REMEMBER: we are using the basic date package in alpine
  today=$(date +"%Y%m%d")
  # could be a delay in minutes or an absolute time of day
  if [[ $DB_DUMP_BEGIN =~ ^\+(.*)$ ]]; then
    waittime=$(( ${BASH_REMATCH[1]} * 60 ))
  else
    target_time=$(date --date="${today}${DB_DUMP_BEGIN}" +"%s")

    if [[ "$target_time" < "$current_time" ]]; then
      target_time=$(($target_time + 24*60*60))
    fi

    waittime=$(($target_time - $current_time))
  fi

  sleep $waittime

  # enter the loop
  while true; do
    # make sure the directory exists
    mkdir -p $TMPDIR

    # what is the name of our target?
    now=$(date -u +"%Y%m%d%H%M%S")
    

	
	databases=`mysql -h $DBSERVER --user=$DBUSER -p$DBPASS -e "SHOW DATABASES;" | grep -Ev "(Database|information_schema|performance_schema)"`
	
	
    # make the dump
    for db in $databases; do	
			TARGET=db_${db}_backup_${now}.gz
			mysqldump -h $DBSERVER -u$DBUSER -p$DBPASS $db | gzip > ${TMPDIR}/${TARGET}
		
		
		# what kind of target do we have? Plain filesystem? smb?
		case "${uri[schema]}" in
		  "file")
			mkdir -p ${uri[path]}
			mv ${TMPDIR}/${TARGET} ${uri[path]}/${TARGET}
			;;
		  "s3")
			# allow for endpoint url override
			[[ -n "$AWS_ENDPOINT_URL" ]] && AWS_ENDPOINT_OPT="--endpoint-url $AWS_ENDPOINT_URL"
			aws ${AWS_ENDPOINT_OPT} s3 cp ${TMPDIR}/${TARGET} ${DB_DUMP_TARGET}/${TARGET}
			/bin/rm ${TMPDIR}/${TARGET}
			;;
		  "azure")
			azure storage blob upload -a ${STORAGE_ACCOUNT_NAME} --container ${STORAGE_CONTAINER} -k ${STORAGE_ACCOUNT_KEY} "${TMPDIR}/${TARGET}"
			;;
		  "smb")
			if [[ -n "${uri[user]}" ]]; then
			  UPASS="-U ${uri[user]}%${uri[password]}"
			else
			  UPASS=
			fi
			if [[ -n "${uri[userdomain]}" ]]; then
			  UDOM="-W ${uri[userdomain]}"
			else
			  UDOM=
			fi

			smbclient -N //${uri[host]}/${uri[share]} ${UPASS} ${UDOM} -c "cd ${uri[sharepath]}; put ${TMPDIR}/${TARGET} ${TARGET}"
			/bin/rm ${TMPDIR}/${TARGET}
		   ;;
		esac
		
	done 

    # wait
    sleep $(($DB_DUMP_FREQ*60))
  done
fi
