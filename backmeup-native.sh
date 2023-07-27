#!/usr/bin/env bash

# Add paths for the script to work better on cron
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/Users/kuldip/homebrew/bin

# Configuration parameters
# If no configuration file is found, let's download and create one.
if [[ ! -f "$HOME/.backmeuprc" ]];
then
    curl -s https://raw.githubusercontent.com/Ardakilic/backmeup/master/.backmeuprc -o $HOME/.backmeuprc
    chmod 400 $HOME/.backmeuprc # This file must have the least permissions as possible.
fi

# Let's Source the configuration file
source $HOME/.backmeuprc

# Check the shell
if [[ -z "$BASH_VERSION" ]];
then
    echo -e "Error: this script requires the BASH shell!"
    exit 1
fi

# Cleanup Function to remove data older than 5 days
function cleanup {
    rm -rf $1/backmeup* #Database dump folder for the time being
    # Remove data older than 5 days from local storage
    find "$FILESROOT/" -type f -name "backmeup-*" -mtime +5 -exec rm -f {} \;

    # If uploading method is set to Dropbox
    if [[ "$METHOD" == "dropbox" ]];
    then
        # Remove data older than 5 days from Dropbox
        dropbox_uploader list "$BACKUPFOLDER" | grep "backmeup-" | while read -r file; do
            created_date=$(echo "$file" | awk '{print $2}')
            file_name=$(echo "$file" | awk '{print $3}')
            file_date=$(date -d "$created_date" +%s)
            current_date=$(date +%s)
            days_diff=$(( (current_date - file_date) / (24 * 60 * 60) ))
            if [ "$days_diff" -gt 5 ]; then
                dropbox_uploader delete "$BACKUPFOLDER/$file_name"
            fi
        done
    fi

    # If uploading method is set to AWS S3
    if [[ "$METHOD" == "s3" ]];
    then
        # Remove data older than 5 days from AWS S3
        aws s3 ls "s3://$S3_BUCKET_NAME/$BACKUPFOLDER" --recursive | grep "backmeup-" | while read -r line; do
            created_date=$(echo "$line" | awk '{print $1, $2}')
            file_name=$(echo "$line" | awk '{print $4}')
            file_date=$(date -d "$created_date" +%s)
            current_date=$(date +%s)
            days_diff=$(( (current_date - file_date) / (24 * 60 * 60) ))
            if [ "$days_diff" -gt 5 ]; then
                aws s3 rm "s3://$S3_BUCKET_NAME/$BACKUPFOLDER/$file_name"
            fi
        done
    fi
}

# Needed for file and folder names
THEDATE=`TZ=$TIMEZONE date +%Y-%m-%d_%H.%M.%S`

INSTALLABLE="yes"
ERRORMSGS=()

# Let's check whether the script is installable
if [[ "$INSTALLABLE" == "yes" ]];
then

    # pre-cleanup
    cleanup $BASEFOLDER
    # folder for new backup
    SQLFOLDER=backmeup-databases-$THEDATE
    SQLFOLDERFULL="$BASEFOLDER/db/$SQLFOLDER"
    mkdir -p "$BASEFOLDER/db/" # to ensure the subfolder exists
    mkdir $SQLFOLDERFULL

    # Let's start dumping the databases
    databases=$(mysql -h$DBHOST -u"$DBUSER" -p"$DBPASSWORD" -P"$DBPORT" -e "SHOW DATABASES;" | tr -d "| " | grep -v Database)
    for db in $databases; do
        # Check if the database is in the skip list
        if [[ ",$SKIP_DB," != *",$db,"* ]]; then
            echo "| Dumping database: $db"
            mysqldump -h"$DBHOST" -u"$DBUSER" -p"$DBPASSWORD" -P"$DBPORT" $db > $SQLFOLDERFULL/$THEDATE.$db.sql
        else
            echo "| Skipping database: $db"
        fi
    done

    echo '|'
    echo '| Done!'
    echo '|'

    # Now let's create the backup file and compress
    echo '| Now compressing the backup...'

    if [[ "$COMPRESSION" == "tar" ]];
    then
        FILENAME="backmeup-$THEDATE.tar.gz"
        tar -czvf "$FILESROOT/$FILENAME" "$SQLFOLDERFULL"
    elif [[ "$COMPRESSION" == "7zip" ]];
    then
        FILENAME="backmeup-$THEDATE.7z"
        if [[ "$SEVENZIP_COMPRESSION_PASSWORD" != "" ]];
        then
            # https://askubuntu.com/a/928301/107722
            7z a -t7z -m0=lzma2 -mx=9 -mfb=64 -md=32m -ms=on -mhe=on -p"$SEVENZIP_COMPRESSION_PASSWORD" "$BASEFOLDER/$FILENAME" "$FILESROOT" "$SQLFOLDERFULL" > /dev/null
        else
            7z a -t7z -m0=lzma2 -mx=9 -mfb=64 -md=32m -ms=on "$BASEFOLDER/$FILENAME" "$FILESROOT" "$SQLFOLDERFULL" > /dev/null
        fi
    fi

    echo '|'
    echo "| Done! The backup's name is: $FILENAME"
    echo '|'
    # Create backup END

    # If uploading method is set to Dropbox
    if [[ "$METHOD" == "dropbox" ]];
        then
        # Now let's fetch Dropbox Uploader
        # https://github.com/andreafabrizi/Dropbox-Uploader
        # to make sure it's always the newest version, first let's delete and fetch it
        # cd $HOME # not needed
        echo '| Fetching the newest Dropbox-Uploader from the repository...'
        rm -rf /usr/local/bin/dropbox_uploader
        curl -s https://raw.githubusercontent.com/andreafabrizi/Dropbox-Uploader/master/dropbox_uploader.sh -o /usr/local/bin/dropbox_uploader
        echo '| Done!'
        echo '-------------------------------------------------'
        # make it executable
        chmod +x /usr/local/bin/dropbox_uploader

        # Is Dropbox-Uploader configured?
        if [[ ! -f "$HOME/.dropbox_uploader" ]];
        then
            echo '| You must configure Dropbox first!'
            echo '| Please run dropbox_uploader as the user who will run this script and follow the instructions.'
            echo '| After that, re-run this script again'
        else
            # Now, let's upload to Dropbox:
            echo '| Creating the directory and uploading to Dropbox...'
            dropbox_uploader mkdir "$BACKUPFOLDER"
            dropbox_uploader upload "$BASEFOLDER/$FILENAME" "$BACKUPFOLDER"
            echo '|'
            echo '| Done!'
            echo '|'
        fi
    elif [[ "$METHOD" == "s3" ]];
    then
        # If uploading method is set to AWS S3
        echo '| Creating the directory and uploading to Amazon S3...'
        aws s3 cp --storage-class $S3_STORAGE_CLASS $FILENAME s3://$S3_BUCKET_NAME/$BACKUPFOLDER/
        echo '|'
        echo '| Done!'
        echo '|'
    elif [[ "$METHOD" == "mega" ]];
    then
        # If uploading method is set to Mega.nz
        echo '| Creating the directory and uploading to Mega.nz...'
        aws mega-put $FILENAME /$BACKUPFOLDER/ -c
        echo '|'
        echo '| Done!'
        echo '|'
    fi

    echo "| Cleaning up... $SQLFOLDERFULL"
    # Now let's cleanup
    cleanup $SQLFOLDERFULL
    echo '|'
    echo "| Done! You should now see your backup '$FILENAME' inside the '$BACKUPFOLDER' in your Backup Solution"

else
    echo '| ERROR:'
    for i in "${ERRORMSGS[@]}"
        do
           echo $i
        done
fi

echo '-------------------------------------------------'

# Let's clean up just in case
cleanup $BASEFOLDER
