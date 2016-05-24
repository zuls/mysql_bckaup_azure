#MySQL or Mariadb backup (mysqldump)

##Features

This container will help you to take all individual schema from a linked container that has a running mysql/mariadb server. 

* dump individual database schema to the Azure blob storage
* connect to any container running on the same system
* select how often to run a dump


##Backup

Example 

````bash
docker run -d --name MySQl-Dump-in-Azure --restart=always \
-e DB_USER=root \
-e DB_PASS=mypass \
-e DB_DUMP_FREQ=60 \
-e DB_DUMP_TARGET=azure://gb5555.blob.core.windows.net/containerx/ \
-e STORAGE_ACCOUNT_NAME=gb5555 \
-e STORAGE_CONTAINER=containerx \
-e STORAGE_ACCOUNT_KEY="U/2reY/R+p7T/Af1f9+F9CDIBQ==" \
--link mysql_container_name:db \
gbuildercom/mysql_dump_azure
````

The above will run a dump every 60 minutes starting immediately, from the mysql or mariadb database accessible in the container `mysql_container_name`.

* `DB_USER`: username for the mysql or mariadb database server. Most of the cases it is 'root'. 
* `DB_PASS`: password for the mysql or mariadb database server.
* `DB_DUMP_FREQ`: How often to do a dump, in minutes. if you want it once per day, set it to 1440.
* `DB_DUMP_TARGET`: Where to put the dump file, should be a directory. Supports three formats:
 * Local: If the value of `DB_DUMP_TARGET` starts with a `/` character, will dump to a local path, which should be volume-mounted.
 * SMB: If the value of `DB_DUMP_TARGET` is a URL of the format `smb://hostname/share/path/` then it will connect via SMB.
 * S3: If the value of `DB_DUMP_TARGET` is a URL of the format `s3://bucketname/path` then it will connect via awscli.
  * `AWS_ACCESS_KEY_ID`: AWS Key ID
  * `AWS_SECRET_ACCESS_KEY`: AWS Secret Access Key
  * `AWS_DEFAULT_REGION`: Region in which the bucket resides
 * Azure: If the value of `DB_DUMP_TARGET` is a URL of the format `azure://endpoint_url/container_name` then it will connect via azure cli.  
  * `STORAGE_ACCOUNT_NAME`: Azure storage account name. 
  * `STORAGE_CONTAINER`: Container name. Chose blob from the Azure storage and get the container name.  
  * `STORAGE_ACCOUNT_KEY`: Azure storage account secret key. You will find that from the storage account settings. 
  
  
  