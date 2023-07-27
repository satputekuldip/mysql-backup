# mysql-backup
Mysql Daily backup Backup and docker mysql and php my admin setup

# Easiest MySQL Setup EVERRRR

This mysql setup will work on all operating system with docker or you can use native mysql setup


## Store your constant file '.backmeuprc' in your /home/user directory 

## Don't forget to update path in .backmeuprc and also in docker-compose.yml file



### CRON job config

```
crontab -e
```
### Add this to end of the file *replace path_to your script path
```
# Backup every hour
0 * * * * /bin/bash /path_to/backmeupnew.sh
```


### For AWS S3 setup add your s3 bucket IAM credentials
```
aws configure 
```
